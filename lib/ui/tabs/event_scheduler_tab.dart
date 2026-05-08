import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/media_item.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import '../../models/event.dart';
import '../../services/storage_service.dart';
import '../../services/media_library_service.dart';
import '../../repositories/firestore_event_repository.dart';
import '../widgets/video_widgets.dart';
import '../../utils/web_file_input_stub.dart'
    if (dart.library.html) '../../utils/web_file_input_web.dart'
    as web_file_input;

class EventSchedulerTab extends StatefulWidget {
  final ValueNotifier<String?>? selectionNotifier;
  final List<Event>? liveEvents;

  const EventSchedulerTab({super.key, this.selectionNotifier, this.liveEvents});

  @override
  State<EventSchedulerTab> createState() => EventSchedulerTabState();
}

class EventSchedulerTabState extends State<EventSchedulerTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // State: Map of "HH:mm" -> Event Data Map
  Map<String, Map<String, dynamic>> _scheduledEventsData = {};
  String? _selectedSlotId; // e.g., "14:30"
  int _selectedWeekOffset = 0; // 0 = Current, 1 = Next Week, etc.

  // Tracks slots explicitly cleared by the user so the grid suppresses live events
  // for those slots even if Firestore deletion hasn't propagated yet.
  Set<String> _deletedSlots = {};

  // True when the currently-selected slot was loaded purely from liveEvents
  // (not from a local draft). Prevents auto-saving liveEvent data back into
  // local draft simply because the user clicked somewhere else.
  bool _currentSlotFromLiveOnly = false;

  // Weekly Drafts
  // Keeps track of drafts for each week offset, so switching weeks doesn't lose work.
  // Key: weekOffset, Value: Map of "HH:mm" -> Event Data
  final Map<int, Map<String, Map<String, dynamic>>> _weeklyDrafts = {};

  bool _isLoading = false;
  double? _uploadProgress;

  // Local preview state
  Uint8List? _localVisualBytes;
  String? _localVisualName;
  String? _localVideoUrl; // Blob URL for local video preview
  String? _localVideoViewId; // Unique ID for the HtmlElementView

  // Active Uploads / Previews (SlotId -> Preview Data)
  // Stores local preview data while upload is in progress so it persists across slot switching
  final Map<String, Map<String, dynamic>> _activeUploads = {};

  // Form Controllers
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _intentController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _visualUrlController = TextEditingController();
  final TextEditingController _soundUrlController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  final TextEditingController _noticeBoardBgController =
      TextEditingController();
  final TextEditingController _noticeBoardBgColorController =
      TextEditingController();
  bool _autoNotify = false;
  bool _isRecurring = false; // Default to false (User request)
  bool _isRandomized = false; // Auto-randomize content daily
  bool _useTrendingIntent = false; // Auto-select most popular intent
  bool _showNoticeBoardPreview = false;
  int _noticeBoardShowBeforeMinutes = 60; // Default 1 hour
  int _noticeBoardVisibilityAfterMinutes =
      0; // Default 0 (hide immediately after end)
  final FocusNode _noticeBoardBgFocus = FocusNode();
  final FocusNode _visualUrlFocus = FocusNode();
  final FocusNode _titleFocus = FocusNode();

  // Intent Groups
  final Map<String, List<String>> _intentGroups = {
    'Spiritual & Inner Growth': [
      'Harmony',
      'Peace',
      'Love',
      'Compassion',
      'Gratitude',
      'Joy',
      'Faith',
      'Trust',
      'Mindfulness',
      'Enlightenment',
      'Inner Peace',
      'Spiritual Awakening',
      'Sacredness',
      'Reverence',
      'Clarity',
      'Purpose',
      'Renewal of Spirit',
    ],
    'Personal Development': [
      'Integrity',
      'Wisdom',
      'Truth',
      'Courage',
      'Patience',
      'Humility',
      'Strength',
      'Resilience',
      'Openness',
      'Acceptance',
      'Empowerment',
      'Growth',
      'Creativity',
      'Balance of Mind and Spirit',
    ],
    'Social & Interpersonal Values': [
      'Kindness',
      'Empathy',
      'Forgiveness',
      'Generosity',
      'Respect',
      'Understanding',
      'Tolerance',
      'Friendship',
      'Honour',
      'Dignity',
      'Inclusion',
      'Cooperation',
      'Unity',
      'Non-violence',
    ],
    'Global & Collective Good': [
      'Justice',
      'Equality',
      'Freedom',
      'Sustainability',
      'Responsibility',
      'Healing the Earth',
      'Global Solidarity',
      'Respect for Diversity',
      'Collective Good',
      'Universal Love',
      'Equality of Opportunity',
    ],
    'Positive Outlook & Emotional Well-being': [
      'Hope',
      'Joyfulness',
      'Serenity',
      'Abundance',
      'Renewal',
      'Benevolence',
      'Gratitude for Life',
      'Joy in Service',
      'Faith in Humanity',
    ],
  };

  String? _selectedIntentCategory;
  String? _selectedIntentValue;

  // Services
  final StorageService _storage = StorageService();
  final FirestoreEventRepository _eventRepository = FirestoreEventRepository();
  // ignore: unused_field
  final MediaLibraryService _mediaLibrary = MediaLibraryService();

  @override
  void initState() {
    super.initState();
    _loadDraftFromLocal();
    _noticeBoardBgFocus.addListener(_onNoticeBoardFocusChange);
    _visualUrlFocus.addListener(_onMainFieldFocusChange);
    _titleFocus.addListener(_onMainFieldFocusChange);

    // Handle external selection (e.g. from Dashboard)
    if (widget.selectionNotifier != null) {
      widget.selectionNotifier!.addListener(_handleExternalSelection);
      // Check for initial value
      if (widget.selectionNotifier!.value != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleExternalSelection();
        });
      }
    }
  }

  @override
  void dispose() {
    if (widget.selectionNotifier != null) {
      widget.selectionNotifier!.removeListener(_handleExternalSelection);
    }
    _titleController.dispose();
    _intentController.dispose();
    _descriptionController.dispose();
    _visualUrlController.dispose();
    _soundUrlController.dispose();
    _durationController.dispose();
    _noticeBoardBgController.dispose();
    _noticeBoardBgFocus.dispose();
    _visualUrlFocus.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _handleExternalSelection() {
    final slotId = widget.selectionNotifier?.value;
    if (slotId != null) {
      _selectSlot(slotId);
      // Clear the notifier so we don't re-select on rebuilds unnecessarily
      widget.selectionNotifier!.value = null;
    }
  }

  /// Calculates the "Target Date" for the selected week offset
  DateTime _getTargetDate() {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    return today.add(Duration(days: 7 * _selectedWeekOffset));
  }

  void _onNoticeBoardFocusChange() {
    if (_noticeBoardBgFocus.hasFocus) {
      setState(() {
        _showNoticeBoardPreview = true;
      });
    }
  }

  void _onMainFieldFocusChange() {
    if (_visualUrlFocus.hasFocus || _titleFocus.hasFocus) {
      setState(() {
        _showNoticeBoardPreview = false;
      });
    }
  }

  // --- Data Management ---

  Future<void> _loadDraftFromLocal() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftString = prefs.getString(
        'eventSchedulerDraftV3_Week$_selectedWeekOffset',
      );
      if (draftString != null) {
        final Map<String, dynamic> decoded = jsonDecode(draftString);
        setState(() {
          _scheduledEventsData = decoded.map(
            (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
          );
        });
      } else {
        setState(() {
          _scheduledEventsData.clear();
        });
      }
      // Restore deleted slots marker
      final deletedString = prefs.getString(
        'eventSchedulerDeletedSlotsV1_Week$_selectedWeekOffset',
      );
      setState(() {
        _deletedSlots = deletedString != null
            ? Set<String>.from(
                (jsonDecode(deletedString) as List).cast<String>())
            : {};
      });
    } catch (e) {
      debugPrint('Error loading draft: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveDraftToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Use offset-specific key to allow saving drafts for different weeks separately
      await prefs.setString(
        'eventSchedulerDraftV3_Week$_selectedWeekOffset',
        jsonEncode(_scheduledEventsData),
      );
      // Persist deleted-slot markers so they survive tab navigation
      await prefs.setString(
        'eventSchedulerDeletedSlotsV1_Week$_selectedWeekOffset',
        jsonEncode(_deletedSlots.toList()),
      );
    } catch (e) {
      debugPrint('Error saving draft (likely quota exceeded): $e');
    }
  }

  /// Public method to select a slot programmatically
  void selectSlot(String slotId) {
    _selectSlot(slotId);
  }

  void _selectSlot(String slotId) {
    // Save current slot before switching, but ONLY if:
    // a) there is already a local draft for it (user previously saved it), OR
    // b) the form was loaded from a local draft (not purely from liveEvents).
    // This prevents clicking between grid tiles from silently resurrecting
    // live events into the local draft without any user intent.
    if (_selectedSlotId != null && !_currentSlotFromLiveOnly) {
      _saveCurrentSlot();
    }

    setState(() {
      _selectedSlotId = slotId;

      // 1. Try to get local draft data
      Map<String, dynamic> data = _scheduledEventsData[slotId] ?? {};
      _currentSlotFromLiveOnly = false; // reset; will be set true below if needed

      // 2. If slot was explicitly cleared OR no local draft, try to find a live event
      //    (but skip liveEvents lookup if slot is in _deletedSlots)
      if (data.isEmpty && !_deletedSlots.contains(slotId) && widget.liveEvents != null) {
        try {
          final parts = slotId.split(':');
          final hour = int.parse(parts[0]);
          final minute = int.parse(parts[1]);
          final targetDate = _getTargetDate(); // Use offset

          final liveEvent = widget.liveEvents!.firstWhere(
            (e) {
              // Filter out Global events from the Scheduler
              if (e.type == 'global') return false;

              if (e.startTimeUTC == null) return false;
              final start = DateTime.parse(e.startTimeUTC!);

              // Check time match
              final timeMatch = start.hour == hour &&
                  start.minute >= minute &&
                  start.minute < minute + 15;
              if (!timeMatch) return false;

              final isTargetDate = start.year == targetDate.year &&
                  start.month == targetDate.month &&
                  start.day == targetDate.day;

              if (isTargetDate) return true;
              if (e.isRecurring == true) return true;

              return false;
            },
            orElse: () =>
                Event(id: '', title: '', type: 'national', isRecurring: true),
          );

          if (liveEvent.id.isNotEmpty) {
            data = _convertEventToMap(liveEvent);
            _currentSlotFromLiveOnly = true; // loaded from liveEvents, not a local draft
          }
        } catch (e) {
          debugPrint('Error matching live event: $e');
        }
      }

      // Restore local preview if active upload exists
      if (_activeUploads.containsKey(slotId)) {
        final preview = _activeUploads[slotId]!;
        _localVisualBytes = preview['bytes'];
        _localVisualName = preview['name'];
        _localVideoUrl = preview['videoUrl'];
        _localVideoViewId = preview['viewId'];
        _visualUrlController.clear();
      } else {
        _localVisualBytes = null;
        _localVisualName = null;
        _localVideoUrl = null;
        _localVideoViewId = null;
        _visualUrlController.text = data['visualUrl'] ?? '';
      }

      _titleController.text = data['title'] ?? '';

      // Handle Intent Parsing
      final savedIntent = data['intent'] as String? ?? '';
      _intentController.text = savedIntent;
      _descriptionController.text = data['description'] as String? ?? '';

      // Try to find category for saved intent
      _selectedIntentCategory = null;
      _selectedIntentValue = null;

      if (savedIntent.isNotEmpty) {
        for (var entry in _intentGroups.entries) {
          if (entry.value.contains(savedIntent)) {
            _selectedIntentCategory = entry.key;
            _selectedIntentValue = savedIntent;
            break;
          }
        }
      }

      // Visual URL handled above
      _soundUrlController.text = data['soundUrl'] ?? '';
      // Default to 10 seconds if empty or null to prevent "missing duration" issues
      _durationController.text = data['durationSeconds']?.toString() ?? '10';
      _noticeBoardBgController.text = data['noticeBoardBgImage'] ?? '';
      _noticeBoardBgColorController.text = data['noticeBoardBgColor'] ?? '';
      _autoNotify = data['autoNotify'] ?? false;
      _isRecurring = data['isRecurring'] ?? false;
      _isRandomized = data['isRandomized'] ?? false;
      _useTrendingIntent = data['useTrendingIntent'] ?? false;
      _noticeBoardShowBeforeMinutes =
          data['noticeBoardShowBeforeMinutes'] ?? 60;
      _noticeBoardVisibilityAfterMinutes =
          data['noticeBoardVisibilityAfterMinutes'] ?? 0;
    });
  }

  String _calculateEndTimeStr() {
      if (_selectedSlotId == null) return "--:--:--";
      
      try {
          // Parse Start Time from Slot ID (HH:mm)
          final parts = _selectedSlotId!.split(':');
          final startHour = int.parse(parts[0]);
          final startMinute = int.parse(parts[1]);
          
          final now = DateTime.now();
          final startTime = DateTime(now.year, now.month, now.day, startHour, startMinute);
          
          final durationSecs = int.tryParse(_durationController.text) ?? 0;
          final endTime = startTime.add(Duration(seconds: durationSecs));
          
          return "${endTime.hour.toString().padLeft(2,'0')}:${endTime.minute.toString().padLeft(2,'0')}:${endTime.second.toString().padLeft(2,'0')}";
      } catch (e) {
          return "--:--:--";
      }
  }

  void _saveCurrentSlot() {
    if (_selectedSlotId == null) return;
    // Remove from deleted set — user is actively editing/keeping this slot.
    _deletedSlots.remove(_selectedSlotId!);
    _currentSlotFromLiveOnly = false;

    final currentData = _scheduledEventsData[_selectedSlotId!] ?? {};

    // Determine visual URL to save
    String visualUrlToSave = _visualUrlController.text;
    // If controller is empty but we have an active upload/preview, preserve the existing map value
    // This prevents overwriting the URL with empty string while an upload is in progress
    if (visualUrlToSave.isEmpty &&
        (_activeUploads.containsKey(_selectedSlotId!) ||
            _localVisualBytes != null)) {
      visualUrlToSave = currentData['visualUrl'] ?? '';
    }

    setState(() {
      _scheduledEventsData[_selectedSlotId!] = {
        ...currentData,
        'title': _titleController.text,
        'intent': _intentController.text,
        'description': _descriptionController.text,
        'visualUrl': visualUrlToSave,
        'soundUrl': _soundUrlController.text,
        'durationSeconds': int.tryParse(_durationController.text.trim()),
        'noticeBoardBgImage': _noticeBoardBgController.text,
        'noticeBoardBgColor': _noticeBoardBgColorController.text,
        'autoNotify': _autoNotify,
        'isRecurring': _isRecurring,
        'isRandomized': _isRandomized,
        'useTrendingIntent': _useTrendingIntent,
        'noticeBoardShowBeforeMinutes': _noticeBoardShowBeforeMinutes,
        'noticeBoardVisibilityAfterMinutes': _noticeBoardVisibilityAfterMinutes,
        'updatedAt': DateTime.now().toIso8601String(),
      };
    });
    _saveDraftToLocal();
  }

  void _clearCurrentSlot() {
    if (_selectedSlotId == null) return;

    final targetDate = _getTargetDate();
    final dateSuffix =
      "${targetDate.year}${targetDate.month.toString().padLeft(2, '0')}${targetDate.day.toString().padLeft(2, '0')}";
    final deterministicPublishedId =
      'slot_${_selectedSlotId!.replaceAll(':', '')}_$dateSuffix';
    final deterministicDraftId =
      'draft_slot_${_selectedSlotId!.replaceAll(':', '')}_$dateSuffix';

    // Determine the ID to delete
    String eventId;

    // 1. Check if we have a stored ID in local draft
    if (_scheduledEventsData[_selectedSlotId]?.containsKey('id') == true) {
      eventId = _scheduledEventsData[_selectedSlotId]!['id'];
    } else {
      // 2. Generate Deterministic ID (re-create logic from _publishSchedule)
        eventId = deterministicPublishedId;

      // 3. Fallback check: Search in live events if the deterministic one isn't the one needed
      // (This is mostly for non-deterministic or legacy IDs, but let's prioritize the deterministic one first because that's what we create)
      if (widget.liveEvents != null) {
        try {
          final parts = _selectedSlotId!.split(':');
          final hour = int.parse(parts[0]);
          final minute = int.parse(parts[1]);
          final liveEvent = widget.liveEvents!.firstWhere((e) {
            // Filter out Global events just like _selectSlot
            if (e.type == 'global') return false;

            if (e.startTimeUTC == null) return false;
            final start = DateTime.parse(e.startTimeUTC!);

            final timeMatch = start.hour == hour &&
                start.minute >= minute &&
                start.minute < minute + 15;
            if (!timeMatch) return false;

            final dateMatch = start.year == targetDate.year &&
              start.month == targetDate.month &&
              start.day == targetDate.day;
            final isRecurring = e.isRecurring == true;

            // Note: If we are editing a specific instance (date match), we prefer that ID.
            // If it's recurring, we might have a different ID structure.
            return dateMatch || isRecurring;
          }, orElse: () => Event(id: '', title: ''));

          if (liveEvent.id.isNotEmpty && liveEvent.id != eventId) {
             // If we found a live event that matches this slot and has a different ID,
             // it usually means we are editing an existing event.
             // However, for TRASH, we want to delete whatever is there.
             // If we have a drift between deterministic ID and actual ID, use the actual one found.
             eventId = liveEvent.id;
          }
        } catch (e) {
          // Ignore fallback errors
        }
      }
    }

    // Mark slot as explicitly deleted — suppresses liveEvent display in the grid
    // even before the Firestore deletion propagates back through the stream.
    _deletedSlots.add(_selectedSlotId!);
    _currentSlotFromLiveOnly = false;

    // Delete all possible IDs for this slot/date (published + draft + discovered ID)
    final idsToDelete = <String>{
      eventId,
      deterministicPublishedId,
      deterministicDraftId,
    };
    if (eventId.startsWith('draft_slot_')) {
      idsToDelete.add(eventId.replaceFirst('draft_slot_', 'slot_'));
    } else if (eventId.startsWith('slot_')) {
      idsToDelete.add(eventId.replaceFirst('slot_', 'draft_slot_'));
    }

    Future.wait(idsToDelete.map((id) => _eventRepository.deleteEvent(id)))
        .then((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event cleared from schedule')),
        );
      }
    }).catchError((e) {
      // Ignore errors if doc doesn't exist
      debugPrint("Error deleting slot docs for ${_selectedSlotId!}: $e");
    });

    setState(() {
      _scheduledEventsData.remove(_selectedSlotId);
      _selectedSlotId =
          null; // Prevent _saveCurrentSlot from resurrecting this on next navigation
    });

    _resetForm();
    _saveDraftToLocal(); // persists both _scheduledEventsData and _deletedSlots
  }

  void _stopLocalVideo() {
    if (kIsWeb) {
      try {
        final video = html.document.getElementById('scheduler_preview_video')
            as html.VideoElement?;
        if (video != null) {
          video.pause();
          video.removeAttribute('src');
          video.load();
        }
      } catch (e) {
        debugPrint("Error stopping local video: $e");
      }
    }
    setState(() {
      _localVisualBytes = null;
      _localVisualName = null;
      _localVideoUrl = null;
      _localVideoViewId = null;
    });
  }

  void _resetForm() {
    _stopLocalVideo();
    _titleController.clear();
    _intentController.clear();
    _descriptionController.clear();
    _visualUrlController.clear();
    _soundUrlController.clear();
    _durationController.clear();
    _noticeBoardBgController.clear();
    _noticeBoardBgColorController.clear();
    setState(() {
      _selectedIntentCategory = null;
      _selectedIntentValue = null;
      _autoNotify = false;
      _isRecurring = false;
      _isRandomized = false;
      _useTrendingIntent = false;
      _noticeBoardShowBeforeMinutes = 60;
      _noticeBoardVisibilityAfterMinutes = 0;
    });
  }

  Future<void> _wipeWeeklyDraft() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Weekly Draft'),
        content: const Text(
          'Are you sure you want to clear ALL draft events for this week from the Scheduler?\n\n'
          'This will NOT delete published events from the app until you click "Save to Dashboard".\n'
          'This helps fix issues where deleted events keep reappearing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Reset Draft',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _selectedSlotId = null;
      _scheduledEventsData.clear();
      _deletedSlots.clear();
      _currentSlotFromLiveOnly = false;
      if (_weeklyDrafts.containsKey(_selectedWeekOffset)) {
        _weeklyDrafts[_selectedWeekOffset]?.clear();
      }
      _resetForm();
    });

    await _saveDraftToLocal(); // Saves empty map + clears persisted deleted slots

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Draft schedule reset. You can now build fresh.'),
        ),
      );
    }
  }

  void _copyWeekToClipboard() {
    // 1. Serialize current week's schedule
    final jsonString = jsonEncode(_scheduledEventsData);

    // 2. Put into clipboard variable (or system clipboard if possible, but in-memory is safer for now)
    // For now we will just store it in a static variable or just assume "Copy" means "hold in memory"
    // But user asked to "Copy a week and paste it into another", so let's stick to in-memory for this session.

    // We can use a standard clipboard if we want cross-session, but let's just make it simple first:
    // We'll store it in a static variable in this class for simplicity
    _copiedWeekData = jsonString;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Week schedule copied! Navigate to another week and click "Paste Week". (${_scheduledEventsData.length} events)',
        ),
      ),
    );
  }

  static String? _copiedWeekData;

  void _pasteWeekFromClipboard() {
    if (_copiedWeekData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard is empty. Copy a week first.')),
      );
      return;
    }

    try {
      final Map<String, dynamic> decoded = jsonDecode(_copiedWeekData!);
      // Convert dynamic map back to our strong-typed map structure
      final Map<String, Map<String, dynamic>> newWeekData = {};

      decoded.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          // We need to regenerate IDs so they don't clash?
          // Actually, _publishSchedule generates IDs based on target date, so we can keep the data as is.
          // BUT, we should probably strip the 'id' field so it regenerates for the new week.
          final eventData = Map<String, dynamic>.from(value);
          eventData.remove('id');
          newWeekData[key] = eventData;
        }
      });

      setState(() {
        _scheduledEventsData = newWeekData;
        _saveDraftToLocal(); // persist immediately
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Schedule pasted successfully! Don\'t forget to Review and Publish.',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error pasting week: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error pasting schedule.')));
    }
  }

  Future<void> _publishSchedule() async {
    if (_scheduledEventsData.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No events to publish')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Convert map to List<Event>
      List<Event> eventsToSave = [];
      int blankSlotsCleared = 0;

      for (final entry in _scheduledEventsData.entries) {
        final slotId = entry.key;
        final data = entry.value;
        // slotId is "HH:mm"
        // We need to construct a startTimeUTC.
        final parts = slotId.split(':');
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);

        // Create a UTC DateTime for this slot based on SELECTED WEEK
        final targetDate = _getTargetDate();
        final eventTime = DateTime.utc(
          targetDate.year,
          targetDate.month,
          targetDate.day,
          hour,
          minute,
        );

        // Generate a deterministic ID based on the Slot Time and Date to prevent duplicates
        // Format: slot_HHmm_yyyyMMdd
        // This ensures if we re-save the same slot for the same day, it overwrites the existing event instead of creating a new one.
        final dateSuffix =
            "${targetDate.year}${targetDate.month.toString().padLeft(2, '0')}${targetDate.day.toString().padLeft(2, '0')}";
        final draftId =
          'draft_slot_${slotId.replaceAll(':', '')}_$dateSuffix';

        final rawShowBefore = data['noticeBoardShowBeforeMinutes'];
        final int parsedShowBefore = rawShowBefore is int
            ? rawShowBefore
            : int.tryParse('${rawShowBefore ?? ''}') ?? 60;
        final int effectiveShowBefore = parsedShowBefore <= 0 ? 60 : parsedShowBefore;

        final title = (data['title'] as String? ?? '').trim();
        final visualUrl = (data['visualUrl'] as String? ?? '').trim();
        final soundUrl = (data['soundUrl'] as String? ?? '').trim();

        // Firestore rule: blank slot (no title, no media) must never persist as
        // an empty doc. Delete both draft and published variants, then skip saving.
        if (title.isEmpty && visualUrl.isEmpty && soundUrl.isEmpty) {
          final idsToDelete = <String>{
            draftId,
            'slot_${slotId.replaceAll(':', '')}_$dateSuffix',
          };
          for (final id in idsToDelete) {
            try { await _eventRepository.deleteEvent(id); } catch (_) {}
          }
          blankSlotsCleared++;
          continue;
        }

        final event = Event(
          id: draftId,

          title: title,
          intent: data['intent'],
          visualUrl: visualUrl.isNotEmpty ? visualUrl : null,
          // Ensure mediaUrl is set for User App compatibility (from visualUrl)
          // User App uses mediaUrl for video/audio playback logic
          mediaUrl: visualUrl.isNotEmpty ? visualUrl : (soundUrl.isNotEmpty ? soundUrl : null),
          soundUrl: soundUrl.isNotEmpty ? soundUrl : null,
          durationSeconds: data['durationSeconds'] ?? 3600,
          startTimeUTC: eventTime.toIso8601String(),
          originTime:
              slotId, // Save the HH:mm string for consistent local time parsing
          isRecurring:
              data['isRecurring'] ?? false, // Default from map or false
          isRandomized: data['isRandomized'] ?? false,
          useTrendingIntent: data['useTrendingIntent'] ?? false,
          autoNotify: data['autoNotify'] ?? false,
            noticeBoardShowBeforeMinutes: effectiveShowBefore,
          noticeBoardVisibilityAfterMinutes:
              data['noticeBoardVisibilityAfterMinutes'] ?? 0,
          noticeBoardBgImage: data['noticeBoardBgImage'],
          noticeBoardBgColor: data['noticeBoardBgColor'],
          // Drafts must not overwrite live published slot docs in Firestore.
          isPublished: false,
          isDraft: true,
          type: 'national', // Explicitly mark as National
          updatedAt: data['updatedAt'] ?? DateTime.now().toIso8601String(),
          // Defaults for removed fields
          learnMoreShowViewer: false,
        );
        eventsToSave.add(event);
      }

      if (eventsToSave.isNotEmpty) {
        await _eventRepository.saveEvents(eventsToSave);
      }

      final blankMsg = blankSlotsCleared > 0
          ? ' ($blankSlotsCleared blank slot(s) removed from Firestore)'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Schedule saved as Draft (${eventsToSave.length} slot(s))$blankMsg. Go to Dashboard to Publish.',
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _getWeekDateRange(int offset) {
    if (offset == 0) return 'This Week';
    if (offset == 1) return 'Next Week';
    final now = DateTime.now();
    // Monday of current week
    final currentMonday = now.subtract(Duration(days: now.weekday - 1));
    // Monday of target week
    final targetMonday = currentMonday.add(Duration(days: 7 * offset));
    final targetSunday = targetMonday.add(const Duration(days: 6));

    final f = DateFormat('MMM d');
    return '${f.format(targetMonday)} - ${f.format(targetSunday)}';
  }

  int _getISOWeekNumber(DateTime date) {
    // Simplistic Week Number Calculation
    // Note: DateFormat('w') isn't always reliable in standard subset, but 'D' is DayOfYear
    final dayOfYear = int.parse(DateFormat('D').format(date));
    int woy = ((dayOfYear - date.weekday + 10) / 7).floor();
    if (woy < 1) return 52;
    if (woy > 52) return 1;
    return woy;
  }

  void _rebuildScheduleData() {
    setState(() {
      _selectedSlotId = null;
      _scheduledEventsData.clear();
      _deletedSlots.clear();
      _currentSlotFromLiveOnly = false;
    });
    // First try to load draft for the new week offset (also restores _deletedSlots)
    _loadDraftFromLocal();
    // If no draft exists, and we are viewing a future week,
    // the UI will show empty or live recurring events as appropriate.
  }

  List<String> _generateTimeSlots() {
    List<String> slots = [];
    for (int i = 0; i < 96; i++) {
      // 24 hours * 4 slots
      final int hour = i ~/ 4;
      final int minute = (i % 4) * 15;
      final String h = hour.toString().padLeft(2, '0');
      final String m = minute.toString().padLeft(2, '0');
      slots.add('$h:$m');
    }
    return slots;
  }

  Future<void> _pickFromMediaLibrary({
    required Function(String) onSelect,
    String? typeFilter,
  }) async {
    String? selectedSection; // Default to null to force selection

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          child: Container(
            width: 900,
            height: 700,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select ${typeFilter ?? 'Media'}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),

                    // Section Filter
                    StreamBuilder<List<MediaItem>>(
                      stream: _mediaLibrary.getMediaStream(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const SizedBox();
                        final allItems = snapshot.data!;
                        final sections = allItems
                            .map((e) => e.section)
                            .toSet()
                            .toList()
                          ..sort();

                        return DropdownButton<String>(
                          value: selectedSection,
                          hint: const Text('Select Category'),
                          items: [
                            const DropdownMenuItem(
                              value: 'All',
                              child: Text('All Categories'),
                            ),
                            ...sections.map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            ),
                          ],
                          onChanged: (val) =>
                              setState(() => selectedSection = val),
                        );
                      },
                    ),

                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: selectedSection == null
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.category,
                                size: 64,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Please select a category from the dropdown above',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        )
                      : StreamBuilder<List<MediaItem>>(
                          stream: _mediaLibrary.getMediaStream(
                            section: selectedSection == 'All'
                                ? null
                                : selectedSection,
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (snapshot.hasError) {
                              return Center(
                                child: Text('Error: ${snapshot.error}'),
                              );
                            }
                            final allItems = snapshot.data ?? [];
                            List<MediaItem> items;

                            if (typeFilter == 'visual') {
                              items = allItems
                                  .where(
                                    (i) =>
                                        i.type == 'image' ||
                                        i.type == 'video' ||
                                        i.type == 'youtube',
                                  )
                                  .toList();
                            } else if (typeFilter != null) {
                              items = allItems
                                  .where((i) => i.type == typeFilter)
                                  .toList();
                            } else {
                              items = allItems;
                            }

                            if (items.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.perm_media,
                                      size: 48,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No ${typeFilter ?? ''} media found in ${selectedSection == 'All' ? 'library' : selectedSection}.',
                                    ),
                                  ],
                                ),
                              );
                            }
                            return GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 1.0,
                              ),
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final item = items[index];
                                final isImage = item.type == 'image';

                                // Robust YouTube detection
                                final urlLower = item.url.toLowerCase();
                                final isYoutube = item.type == 'youtube' ||
                                    urlLower.contains('youtube') ||
                                    urlLower.contains('youtu.be');
                                final isVideo =
                                    item.type == 'video' || isYoutube;

                                Widget content;
                                if (isImage) {
                                  content = Image.network(
                                    item.url,
                                    fit: BoxFit.cover,
                                  );
                                } else if (isVideo) {
                                  content = VideoGridItem(
                                    url: item.url,
                                    type: isYoutube ? 'youtube' : 'upload',
                                    enablePreview: true,
                                    autoPlay: false,
                                  );
                                } else {
                                  content = const Center(
                                    child: Icon(Icons.audiotrack, size: 48),
                                  );
                                }

                                return InkWell(
                                  onTap: () {
                                    onSelect(item.url);
                                    Navigator.pop(context);
                                  },
                                  child: Card(
                                    clipBehavior: Clip.antiAlias,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          child: IgnorePointer(child: content),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(4.0),
                                          child: Text(
                                            item.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _uploadWithProgress(
    Uint8List bytes,
    String fileName,
    String folder,
    Function(String) onSuccess,
  ) async {
    setState(() {
      _isLoading = true;
      _uploadProgress = 0.0;
    });

    try {
      final ext = fileName.contains('.') ? fileName.split('.').last : 'bin';
      final url = await _storage.uploadBytesWithProgress(
        bytes,
        fileExt: ext,
        folder: folder,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );

      onSuccess(url);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Upload complete!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _pickAndUploadNoticeBoardBg() async {
    final uploadingSlotId = _selectedSlotId;
    if (uploadingSlotId == null) return;

    if (kIsWeb) {
      final wf = await web_file_input.pickFileViaHtml();
      if (wf != null) {
        await _uploadWithProgress(wf.bytes, wf.name, 'scheduler_notice_board', (
          url,
        ) {
          if (mounted) {
            if (_scheduledEventsData[uploadingSlotId] == null) {
              _scheduledEventsData[uploadingSlotId] = {};
            }
            _scheduledEventsData[uploadingSlotId]!['noticeBoardBgImage'] = url;
            _saveDraftToLocal();

            if (_selectedSlotId == uploadingSlotId) {
              setState(() {
                _noticeBoardBgController.text = url;
              });
            }
          }
        });
        return;
      }
    }

    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.bytes != null) {
      await _uploadWithProgress(
        result.files.single.bytes!,
        result.files.single.name,
        'scheduler_notice_board',
        (url) {
          if (mounted) {
            if (_scheduledEventsData[uploadingSlotId] == null) {
              _scheduledEventsData[uploadingSlotId] = {};
            }
            _scheduledEventsData[uploadingSlotId]!['noticeBoardBgImage'] = url;
            _saveDraftToLocal();

            if (_selectedSlotId == uploadingSlotId) {
              setState(() {
                _noticeBoardBgController.text = url;
              });
            }
          }
        },
      );
    }
  }

  Future<void> _uploadAudio() async {
    final uploadingSlotId = _selectedSlotId;
    if (uploadingSlotId == null) return;

    if (kIsWeb) {
      final wf = await web_file_input.pickFileViaHtml();
      if (wf != null) {
        await _uploadWithProgress(wf.bytes, wf.name, 'scheduler_audio', (url) {
          if (mounted) {
            // Update data for the specific slot that initiated the upload
            if (_scheduledEventsData[uploadingSlotId] == null) {
              _scheduledEventsData[uploadingSlotId] = {};
            }
            _scheduledEventsData[uploadingSlotId]!['soundUrl'] = url;
            _saveDraftToLocal();

            // Only update UI if we are still on the same slot
            if (_selectedSlotId == uploadingSlotId) {
              setState(() {
                _soundUrlController.text = url;
              });
            }
          }
        });
        return;
      }
    }

    // Fallback for non-web
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'ogg', 'm4a', 'mp4', 'aac'],
    );
    if (result != null && result.files.single.bytes != null) {
      await _uploadWithProgress(
        result.files.single.bytes!,
        result.files.single.name,
        'scheduler_audio',
        (url) {
          if (mounted) {
            if (_scheduledEventsData[uploadingSlotId] == null) {
              _scheduledEventsData[uploadingSlotId] = {};
            }
            _scheduledEventsData[uploadingSlotId]!['soundUrl'] = url;
            _saveDraftToLocal();

            if (_selectedSlotId == uploadingSlotId) {
              setState(() {
                _soundUrlController.text = url;
              });
            }
          }
        },
      );
    }
  }

  Future<void> _pickImage() async {
    final uploadingSlotId = _selectedSlotId;
    if (uploadingSlotId == null) return;

    if (kIsWeb) {
      final wf = await web_file_input.pickFileViaHtml();
      if (wf != null) {
        // Set local preview immediately
        final name = wf.name.toLowerCase();
        final isVideo = name.endsWith('.mp4') ||
            name.endsWith('.mov') ||
            name.endsWith('.webm');
        final isPdf = name.endsWith('.pdf');

        String? blobUrl;
        String? viewId;

        if (isVideo) {
          // Create Blob URL for video preview
          final blob = html.Blob([wf.bytes]);
          blobUrl = html.Url.createObjectUrlFromBlob(blob);
          viewId = 'video-preview-${DateTime.now().millisecondsSinceEpoch}';

          // Register view factory
          // ignore: undefined_prefixed_name
          ui_web.platformViewRegistry.registerViewFactory(viewId, (int viewId) {
            final video = html.VideoElement()
              ..id = 'scheduler_preview_video' // Fixed ID for cleanup
              ..src = blobUrl!
              ..autoplay = true
              ..loop = true
              ..muted = false // User requested sound
              ..controls = true // Allow user to control playback
              ..style.objectFit = 'cover'
              ..style.width = '100%'
              ..style.height = '100%';

            // Apply duration limit dynamically
            video.onTimeUpdate.listen((event) {
              final durationStr = _durationController.text;
              final durationLimit = int.tryParse(durationStr);
              if (durationLimit != null && durationLimit > 0) {
                if (video.currentTime > durationLimit) {
                  video.currentTime = 0;
                  video.play();
                }
              }
            });
            return video;
          });
        } else if (isPdf) {
          final blob = html.Blob([wf.bytes], 'application/pdf');
          blobUrl = html.Url.createObjectUrlFromBlob(blob);
          viewId = 'pdf-preview-${DateTime.now().millisecondsSinceEpoch}';

          // ignore: undefined_prefixed_name
          ui_web.platformViewRegistry.registerViewFactory(viewId, (int viewId) {
            final element = html.ObjectElement()
              ..data = blobUrl!
              ..type = 'application/pdf'
              ..style.border = 'none'
              ..style.width = '100%'
              ..style.height = '100%';
            return element;
          });
        }

        setState(() {
          _localVisualBytes = Uint8List.fromList(wf.bytes);
          _localVisualName = wf.name;
          _localVideoUrl = blobUrl;
          _localVideoViewId = viewId;
          _visualUrlController.clear(); // Clear URL to force local preview

          // Store in active uploads so it persists if user switches slots
          _activeUploads[uploadingSlotId] = {
            'bytes': _localVisualBytes,
            'name': _localVisualName,
            'videoUrl': _localVideoUrl,
            'viewId': _localVideoViewId,
          };
        });

        // Start upload in background (non-blocking)
        _uploadWithProgress(wf.bytes, wf.name, 'scheduler_images', (url) {
          if (mounted) {
            // Update data for the specific slot that initiated the upload
            if (_scheduledEventsData[uploadingSlotId] == null) {
              _scheduledEventsData[uploadingSlotId] = {};
            }
            _scheduledEventsData[uploadingSlotId]!['visualUrl'] = url;
            _saveDraftToLocal();

            // Remove from active uploads as it is done
            _activeUploads.remove(uploadingSlotId);

            // Only update UI if we are still on the same slot
            if (_selectedSlotId == uploadingSlotId) {
              setState(() {
                _visualUrlController.text = url;
                // We can clear local preview now, or keep it.
                // Clearing it switches to the remote URL which is safer for verification.
                _localVisualBytes = null;
                _localVideoUrl = null;
              });
            }
          }
        });
        return;
      }
    }

    // Fallback for non-web
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );
    if (result != null && result.files.single.bytes != null) {
      // Set local preview immediately
      setState(() {
        _localVisualBytes = result.files.single.bytes;
        _localVisualName = result.files.single.name;
        _visualUrlController.clear();
      });

      await _uploadWithProgress(
        result.files.single.bytes!,
        result.files.single.name,
        'scheduler_images',
        (url) {
          if (mounted) {
            if (_scheduledEventsData[uploadingSlotId] == null) {
              _scheduledEventsData[uploadingSlotId] = {};
            }
            _scheduledEventsData[uploadingSlotId]!['visualUrl'] = url;
            _saveDraftToLocal();

            if (_selectedSlotId == uploadingSlotId) {
              setState(() {
                _visualUrlController.text = url;
              });
            }
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final slots = _generateTimeSlots();

    return Scaffold(
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '24-Hour Event Scheduler',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    // Action Buttons
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _clearCurrentSlot,
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.orange,
                          ),
                          label: const Text(
                            'Clear Slot',
                            style: TextStyle(color: Colors.orange),
                          ), // Shortened text
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.orange),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _publishSchedule,
                          icon: const Icon(Icons.save),
                          label: const Text(
                              'Save Draft'), // Renamed from Save Week
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade800,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Toggle Buttons for Week Selection (Previous/Next)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.indigo.shade100),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _getWeekDateRange(_selectedWeekOffset),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade900,
                        ),
                      ),

                      // Navigation Arrows
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios, size: 16),
                            onPressed: _selectedWeekOffset > 0
                                ? () {
                                    setState(() => _selectedWeekOffset--);
                                    _rebuildScheduleData();
                                  }
                                : null,
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_ios, size: 16),
                            onPressed: () {
                              setState(() => _selectedWeekOffset++);
                              _rebuildScheduleData();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Panel: 48-Slot Grid
                      Expanded(
                        flex: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12.0),
                                child: Text(
                                  'Time Slots',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GridView.builder(
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount:
                                        6, // Increased columns for smaller items
                                    childAspectRatio: 1.0,
                                    crossAxisSpacing: 6,
                                    mainAxisSpacing: 6,
                                  ),
                                  itemCount: slots.length,
                                  itemBuilder: (context, index) {
                                    final slotId = slots[index];
                                    final hasLocalData = _scheduledEventsData
                                        .containsKey(slotId);
                                    final isSelected =
                                        _selectedSlotId == slotId;
                                    final localData =
                                        _scheduledEventsData[slotId];

                                    // Check for live event in this slot
                                    Event? liveEvent;
                                    if (widget.liveEvents != null) {
                                      try {
                                        final parts = slotId.split(':');
                                        final hour = int.parse(parts[0]);
                                        final minute = int.parse(parts[1]);

                                        final targetDate = _getTargetDate();

                                        liveEvent =
                                            widget.liveEvents!.firstWhere(
                                          (e) {
                                            if (e.startTimeUTC == null) {
                                              return false;
                                            }
                                            final start = DateTime.parse(
                                              e.startTimeUTC!,
                                            );

                                            final timeMatch = start.hour == hour &&
                                                start.minute >= minute &&
                                                start.minute < minute + 15;
                                            if (!timeMatch) return false;

                                            final isTargetDate =
                                                start.year == targetDate.year &&
                                                    start.month == targetDate.month &&
                                                    start.day == targetDate.day;

                                            final isRecurring = e.isRecurring == true;

                                            return isTargetDate || isRecurring;
                                          },
                                        );
                                      } catch (_) {}
                                    }

                                    // A slot is considered empty if:
                                    // - there's no local draft AND no live event, OR
                                    // - it was explicitly cleared by the user (_deletedSlots)
                                    final hasData =
                                        (hasLocalData || liveEvent != null) &&
                                        !_deletedSlots.contains(slotId);

                                    // Determine status color
                                    Color statusColor =
                                        Colors.grey.shade300; // Default: Empty

                                    if (hasData) {
                                      if (hasLocalData) {
                                        // Draft status - Amber for unpublished drafts
                                        statusColor = Colors.amber;
                                      } else {
                                        // Published event: green for the entire Mon-Sun week
                                        // it belongs to; amber only once that Sunday has passed.
                                        final now = DateTime.now().toUtc();
                                        final today = DateTime.utc(now.year, now.month, now.day);
                                        final daysSinceMonday = today.weekday - 1;
                                        final weekMonday = today.subtract(Duration(days: daysSinceMonday));
                                        final targetWeekMonday = weekMonday.add(Duration(days: 7 * _selectedWeekOffset));
                                        final targetWeekSunday = targetWeekMonday.add(const Duration(days: 6));
                                        final targetWeekEnd = DateTime.utc(targetWeekSunday.year, targetWeekSunday.month, targetWeekSunday.day, 23, 59, 59);
                                        statusColor = now.isBefore(targetWeekEnd) ? Colors.green : Colors.amber;
                                      }
                                    }

                                    // Tooltip message
                                    String tooltip = slotId;
                                    if (hasLocalData) {
                                      tooltip +=
                                          ' - ${localData?['title']} (Draft)';
                                    } else if (liveEvent != null) {
                                      tooltip += ' - ${liveEvent.title} (Live)';
                                    }

                                    return InkWell(
                                      onTap: () => _selectSlot(slotId),
                                      child: Tooltip(
                                        message: tooltip,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.1),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isSelected
                                                  ? Colors.indigo
                                                  : statusColor,
                                              width: isSelected ? 2 : 1,
                                            ),
                                          ),
                                          child: Center(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration: BoxDecoration(
                                                    color: statusColor,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  slotId,
                                                  style: TextStyle(
                                                    fontWeight: isSelected
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                    color: Colors.grey.shade700,
                                                    fontSize: 8, // Smaller font
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Middle Panel: Editor
                      Expanded(
                        flex: 1,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: _selectedSlotId == null
                              ? const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.touch_app,
                                        size: 48,
                                        color: Colors.grey,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'Select a time slot to edit',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.edit_calendar,
                                            color: Colors.indigo,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Editing Slot: $_selectedSlotId',
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 32),

                                      // Title
                                      Row(
                                        children: [
                                          Expanded(
                                            flex: 2,
                                            child: TextFormField(
                                              controller: _titleController,
                                              focusNode: _titleFocus,
                                              decoration: const InputDecoration(
                                                labelText: 'Event Title',
                                                border: OutlineInputBorder(),
                                                prefixIcon: Icon(Icons.title),
                                              ),
                                              onTap: () => setState(
                                                () => _showNoticeBoardPreview =
                                                    false,
                                              ),
                                              onChanged: (_) =>
                                                  _saveCurrentSlot(),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            flex: 1,
                                            child: TextFormField(
                                               controller: _durationController,
                                               decoration: const InputDecoration(
                                                 labelText: 'Duration (Seconds)',
                                                 helperText: 'Enter exact seconds (e.g. 10)',
                                                 border: OutlineInputBorder(),
                                                 prefixIcon: Icon(Icons.timer_outlined),
                                               ),
                                               keyboardType: TextInputType.number,
                                               onChanged: (_) {
                                                  setState(() {}); // Trigger rebuild to update calculated end time
                                                  _saveCurrentSlot();
                                               },
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          // Display Calculated End Time
                                          Expanded(
                                              flex: 1,
                                              child: Container(
                                                  padding: const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                      border: Border.all(color: Colors.grey),
                                                      borderRadius: BorderRadius.circular(4),
                                                      color: Colors.grey.shade100,
                                                  ),
                                                  child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                          const Text("End Time (Calc):", style: TextStyle(fontSize: 10, color: Colors.grey)),
                                                          Text(
                                                              _calculateEndTimeStr(),
                                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                                          ),
                                                      ],
                                                  ),
                                              ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),

                                      // Intent Dropdowns
                                      Row(
                                        children: [
                                          Expanded(
                                            child:
                                                DropdownButtonFormField<String>(
                                              isExpanded: true,
                                              initialValue:
                                                  _selectedIntentCategory,
                                              decoration: const InputDecoration(
                                                labelText: 'Intent Category',
                                                border: OutlineInputBorder(),
                                                prefixIcon: Icon(
                                                  Icons.category,
                                                ),
                                              ),
                                              items: _intentGroups.keys.map((
                                                cat,
                                              ) {
                                                return DropdownMenuItem(
                                                  value: cat,
                                                  child: Text(
                                                    cat,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                              onChanged: (val) {
                                                setState(() {
                                                  _selectedIntentCategory = val;
                                                  _selectedIntentValue =
                                                      null; // Reset specific intent
                                                  _intentController.clear();
                                                  _showNoticeBoardPreview =
                                                      false;
                                                });
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child:
                                                DropdownButtonFormField<String>(
                                              isExpanded: true,
                                              initialValue:
                                                  _selectedIntentValue,
                                              decoration: const InputDecoration(
                                                labelText: 'Specific Intent',
                                                border: OutlineInputBorder(),
                                              ),
                                              items: _selectedIntentCategory ==
                                                      null
                                                  ? []
                                                  : _intentGroups[
                                                          _selectedIntentCategory]!
                                                      .map((intent) {
                                                      return DropdownMenuItem(
                                                        value: intent,
                                                        child: Text(
                                                          intent,
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                      );
                                                    }).toList(),
                                              onChanged:
                                                  _selectedIntentCategory ==
                                                          null
                                                      ? null
                                                      : (val) {
                                                          setState(() {
                                                            _selectedIntentValue =
                                                                val;
                                                            _intentController
                                                                    .text =
                                                                val ?? '';
                                                            _showNoticeBoardPreview =
                                                                false;
                                                          });
                                                          _saveCurrentSlot();
                                                        },
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),

                                      // Description / Content
                                      TextFormField(
                                        controller: _descriptionController,
                                        decoration: const InputDecoration(
                                          labelText: 'Description / Content',
                                          border: OutlineInputBorder(),
                                          prefixIcon: Icon(Icons.description),
                                          hintText:
                                              'Add details, affirmations, or content for this slot...',
                                        ),
                                        maxLines: 3,
                                        onTap: () => setState(
                                          () => _showNoticeBoardPreview = false,
                                        ),
                                        onChanged: (_) => _saveCurrentSlot(),
                                      ),
                                      const SizedBox(height: 16),

                                      // Visual URL
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              controller: _visualUrlController,
                                              focusNode: _visualUrlFocus,
                                              decoration: const InputDecoration(
                                                labelText: 'Visual / Image URL',
                                                border: OutlineInputBorder(),
                                                prefixIcon: Icon(Icons.image),
                                              ),
                                              onTap: () => setState(
                                                () => _showNoticeBoardPreview =
                                                    false,
                                              ),
                                              onChanged: (_) =>
                                                  _saveCurrentSlot(),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          PopupMenuButton<String>(
                                            icon: const Icon(
                                              Icons.add_photo_alternate,
                                              color: Colors.indigo,
                                            ),
                                            tooltip: 'Select Image Source',
                                            onSelected: (value) {
                                              if (value == 'upload') {
                                                _pickImage();
                                              } else if (value == 'library') {
                                                _pickFromMediaLibrary(
                                                  typeFilter:
                                                      'visual', // Custom filter for image+video
                                                  onSelect: (url) {
                                                    setState(() {
                                                      _visualUrlController
                                                          .text = url;
                                                      _showNoticeBoardPreview =
                                                          false;
                                                    });
                                                    _saveCurrentSlot();
                                                  },
                                                );
                                              } else if (value == 'clear') {
                                                _stopLocalVideo();
                                                setState(() {
                                                  _visualUrlController.clear();
                                                });
                                                _saveCurrentSlot();
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              const PopupMenuItem(
                                                value: 'library',
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.photo_library,
                                                      color: Colors.grey,
                                                    ),
                                                    SizedBox(width: 8),
                                                    Text('Select from Library'),
                                                  ],
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: 'clear',
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.delete_outline,
                                                      color: Colors.red,
                                                    ),
                                                    SizedBox(width: 8),
                                                    Text(
                                                      'Clear / Remove',
                                                      style: TextStyle(
                                                        color: Colors.red,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      if (_isLoading && _uploadProgress != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8.0,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              LinearProgressIndicator(
                                                value: _uploadProgress,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Uploading: ${((_uploadProgress ?? 0) * 100).toStringAsFixed(0)}%',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      const SizedBox(height: 16),

                                      // Sound URL
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              controller: _soundUrlController,
                                              decoration: const InputDecoration(
                                                labelText: 'Sound / Audio URL',
                                                border: OutlineInputBorder(),
                                                prefixIcon: Icon(
                                                  Icons.audiotrack,
                                                ),
                                              ),
                                              onTap: () => setState(
                                                () => _showNoticeBoardPreview =
                                                    false,
                                              ),
                                              onChanged: (_) =>
                                                  _saveCurrentSlot(),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          PopupMenuButton<String>(
                                            icon: const Icon(
                                              Icons.audio_file,
                                              color: Colors.indigo,
                                            ),
                                            tooltip: 'Select Audio Source',
                                            onSelected: (value) {
                                              if (value == 'library') {
                                                _pickFromMediaLibrary(
                                                  typeFilter: 'audio',
                                                  onSelect: (url) {
                                                    setState(
                                                      () => _soundUrlController
                                                          .text = url,
                                                    );
                                                    _saveCurrentSlot();
                                                  },
                                                );
                                              } else if (value == 'clear') {
                                                setState(() {
                                                  _soundUrlController.clear();
                                                });
                                                _saveCurrentSlot();
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              const PopupMenuItem(
                                                value: 'library',
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.photo_library,
                                                      color: Colors.grey,
                                                    ),
                                                    SizedBox(width: 8),
                                                    Text('Select from Library'),
                                                  ],
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: 'clear',
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.delete_outline,
                                                      color: Colors.red,
                                                    ),
                                                    SizedBox(width: 8),
                                                    Text(
                                                      'Clear / Remove',
                                                      style: TextStyle(
                                                        color: Colors.red,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),

                                      // Visibility Settings
                                      const Text(
                                        'Visibility Settings',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),

                                      // Show Before Slider
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.visibility,
                                            size: 20,
                                            color: Colors.grey,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Show on Notice Board: ${_noticeBoardShowBeforeMinutes >= 60 ? "${(_noticeBoardShowBeforeMinutes / 60).toStringAsFixed(1)} hours" : "$_noticeBoardShowBeforeMinutes mins"} before event',
                                                ),
                                                Slider(
                                                  value:
                                                      _noticeBoardShowBeforeMinutes
                                                          .toDouble()
                                                          .clamp(
                                                            0,
                                                            1440,
                                                          ), // Max 24 hours
                                                  min: 0,
                                                  max: 1440,
                                                  divisions: 96, // 15 min steps
                                                  label:
                                                      '${(_noticeBoardShowBeforeMinutes / 60).toStringAsFixed(1)} hours',
                                                  onChanged: (val) {
                                                    setState(
                                                      () =>
                                                          _noticeBoardShowBeforeMinutes =
                                                              val.toInt(),
                                                    );
                                                    _saveCurrentSlot();
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),

                                      // Hide After Slider
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.visibility_off,
                                            size: 20,
                                            color: Colors.grey,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Keep on Notice Board: ${_noticeBoardVisibilityAfterMinutes >= 60 ? "${(_noticeBoardVisibilityAfterMinutes / 60).toStringAsFixed(1)} hours" : "$_noticeBoardVisibilityAfterMinutes mins"} after event ends',
                                                ),
                                                Slider(
                                                  value:
                                                      _noticeBoardVisibilityAfterMinutes
                                                          .toDouble()
                                                          .clamp(
                                                            0,
                                                            1440,
                                                          ), // Max 24 hours
                                                  min: 0,
                                                  max: 1440,
                                                  divisions: 96, // 15 min steps
                                                  label:
                                                      '${(_noticeBoardVisibilityAfterMinutes / 60).toStringAsFixed(1)} hours',
                                                  onChanged: (val) {
                                                    setState(
                                                      () =>
                                                          _noticeBoardVisibilityAfterMinutes =
                                                              val.toInt(),
                                                    );
                                                    _saveCurrentSlot();
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),

                                      // Notice Board Preview
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton.icon(
                                          onPressed: () {
                                            setState(() {
                                              _showNoticeBoardPreview = true;
                                            });
                                          },
                                          icon: const Icon(Icons.visibility),
                                          label: const Text(
                                            'Preview National Notice Board',
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.all(16),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),

                                      // Auto-Randomize
                                      SwitchListTile(
                                        value: _isRandomized,
                                        onChanged: (val) {
                                          setState(() => _isRandomized = val);
                                          _saveCurrentSlot();
                                        },
                                        title: const Text(
                                          'Auto-Randomize Content',
                                        ),
                                        subtitle: const Text(
                                          'Automatically pick new random content daily',
                                        ),
                                        secondary: const Icon(Icons.shuffle),
                                        activeThumbColor: Colors.orange,
                                      ),

                                      // Auto-Trending
                                      SwitchListTile(
                                        value: _useTrendingIntent,
                                        onChanged: (val) {
                                          setState(
                                            () => _useTrendingIntent = val,
                                          );
                                          _saveCurrentSlot();
                                        },
                                        title: const Text(
                                          'Use Community Signal',
                                        ),
                                        subtitle: const Text(
                                          'Auto-fill from recent user intent trends. Turn off to set your own shared intent.',
                                        ),
                                        secondary: const Icon(
                                          Icons.trending_up,
                                        ),
                                        activeThumbColor: Colors.purple,
                                      ),

                                      // Auto-Notify
                                      SwitchListTile(
                                        value: _autoNotify,
                                        onChanged: (val) {
                                          setState(() => _autoNotify = val);
                                          _saveCurrentSlot();
                                        },
                                        title: const Text(
                                          'Send Push Notification',
                                        ),
                                        subtitle: const Text(
                                          'Notify users when this event starts',
                                        ),
                                        secondary: const Icon(
                                          Icons.notifications_active,
                                        ),
                                      ),

                                      const SizedBox(height: 32),
                                    ],
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Right Panel: Phone Preview
                      Expanded(
                        flex: 1,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(bottom: 16.0),
                                child: Text(
                                  'Device Preview',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: AspectRatio(
                                    aspectRatio: 9 /
                                        19.5, // Typical modern phone aspect ratio
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius: BorderRadius.circular(30),
                                        border: Border.all(
                                          color: Colors.black,
                                          width: 8,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.2,
                                            ),
                                            blurRadius: 20,
                                            offset: const Offset(0, 10),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(20),
                                        child: _showNoticeBoardPreview
                                            ? _buildNoticeBoardPreview()
                                            : Stack(
                                                children: [
                                                  // Background Visual
                                                  Positioned.fill(
                                                    child: Builder(
                                                      builder: (context) {
                                                        // 1. Check Local Preview First
                                                        if (_localVisualBytes !=
                                                            null) {
                                                          final name =
                                                              _localVisualName
                                                                      ?.toLowerCase() ??
                                                                  '';
                                                          final isLocalVideo =
                                                              name.endsWith(
                                                                    '.mp4',
                                                                  ) ||
                                                                  name.endsWith(
                                                                    '.mov',
                                                                  ) ||
                                                                  name.endsWith(
                                                                    '.webm',
                                                                  ) ||
                                                                  name.endsWith(
                                                                    '.mpeg4',
                                                                  ) ||
                                                                  name.endsWith(
                                                                    '.mkv',
                                                                  ) ||
                                                                  name.endsWith(
                                                                    '.avi',
                                                                  );
                                                          final isPdf = name
                                                              .endsWith('.pdf');
                                                          final isDoc =
                                                              name.endsWith(
                                                                    '.ppt',
                                                                  ) ||
                                                                  name.endsWith(
                                                                    '.pptx',
                                                                  ) ||
                                                                  name.endsWith(
                                                                    '.doc',
                                                                  ) ||
                                                                  name.endsWith(
                                                                    '.docx',
                                                                  );

                                                          if (isLocalVideo) {
                                                            if (kIsWeb &&
                                                                _localVideoViewId !=
                                                                    null) {
                                                              return HtmlElementView(
                                                                viewType:
                                                                    _localVideoViewId!,
                                                              );
                                                            }
                                                            // Fallback for non-web or if view ID missing
                                                            return Container(
                                                              color:
                                                                  Colors.black,
                                                              child: Center(
                                                                child: Column(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .center,
                                                                  children: [
                                                                    const Icon(
                                                                      Icons
                                                                          .videocam,
                                                                      color: Colors
                                                                          .white54,
                                                                      size: 48,
                                                                    ),
                                                                    const SizedBox(
                                                                      height: 8,
                                                                    ),
                                                                    const Text(
                                                                      'Video Selected',
                                                                      style:
                                                                          TextStyle(
                                                                        color: Colors
                                                                            .white70,
                                                                        fontSize:
                                                                            12,
                                                                      ),
                                                                    ),
                                                                    Padding(
                                                                      padding:
                                                                          const EdgeInsets
                                                                              .all(
                                                                        8.0,
                                                                      ),
                                                                      child:
                                                                          Text(
                                                                        _localVisualName ??
                                                                            'Unknown',
                                                                        style:
                                                                            const TextStyle(
                                                                          color:
                                                                              Colors.white30,
                                                                          fontSize:
                                                                              10,
                                                                        ),
                                                                        textAlign:
                                                                            TextAlign.center,
                                                                        maxLines:
                                                                            1,
                                                                        overflow:
                                                                            TextOverflow.ellipsis,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            );
                                                          } else if (isPdf) {
                                                            if (kIsWeb &&
                                                                _localVideoViewId !=
                                                                    null) {
                                                              // Reusing _localVideoViewId for PDF view ID
                                                              return Stack(
                                                                children: [
                                                                  HtmlElementView(
                                                                    viewType:
                                                                        _localVideoViewId!,
                                                                  ),
                                                                  Positioned(
                                                                    top: 8,
                                                                    right: 8,
                                                                    child:
                                                                        IconButton(
                                                                      icon:
                                                                          const Icon(
                                                                        Icons
                                                                            .open_in_new,
                                                                        color: Colors
                                                                            .black,
                                                                      ),
                                                                      tooltip:
                                                                          'Open PDF in New Tab',
                                                                      onPressed: () => html
                                                                          .window
                                                                          .open(
                                                                        _localVideoUrl!,
                                                                        '_blank',
                                                                      ),
                                                                      style: IconButton
                                                                          .styleFrom(
                                                                        backgroundColor: Colors
                                                                            .white
                                                                            .withOpacity(
                                                                          0.7,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              );
                                                            }
                                                            return const Center(
                                                              child: Icon(
                                                                Icons
                                                                    .picture_as_pdf,
                                                                color: Colors
                                                                    .white,
                                                                size: 48,
                                                              ),
                                                            );
                                                          } else if (isDoc) {
                                                            return Center(
                                                              child: Column(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .center,
                                                                children: [
                                                                  const Icon(
                                                                    Icons
                                                                        .description,
                                                                    color: Colors
                                                                        .white54,
                                                                    size: 48,
                                                                  ),
                                                                  const SizedBox(
                                                                    height: 8,
                                                                  ),
                                                                  const Text(
                                                                    'Document Selected',
                                                                    style:
                                                                        TextStyle(
                                                                      color: Colors
                                                                          .white70,
                                                                    ),
                                                                  ),
                                                                  Padding(
                                                                    padding:
                                                                        const EdgeInsets
                                                                            .all(
                                                                      8.0,
                                                                    ),
                                                                    child: Text(
                                                                      'Preview will be available after upload completes.',
                                                                      style:
                                                                          TextStyle(
                                                                        color: Colors
                                                                            .white
                                                                            .withOpacity(
                                                                          0.5,
                                                                        ),
                                                                        fontSize:
                                                                            10,
                                                                      ),
                                                                      textAlign:
                                                                          TextAlign
                                                                              .center,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            );
                                                          } else {
                                                            return Image.memory(
                                                              _localVisualBytes!,
                                                              fit: BoxFit.cover,
                                                              errorBuilder: (_,
                                                                      __,
                                                                      ___) =>
                                                                  Container(
                                                                color: Colors
                                                                    .grey
                                                                    .shade800,
                                                                child:
                                                                    const Center(
                                                                  child: Icon(
                                                                    Icons
                                                                        .broken_image,
                                                                    color: Colors
                                                                        .white24,
                                                                  ),
                                                                ),
                                                              ),
                                                            );
                                                          }
                                                        }

                                                        // 2. Fallback to URL
                                                        return ValueListenableBuilder<
                                                            TextEditingValue>(
                                                          valueListenable:
                                                              _visualUrlController,
                                                          builder: (context,
                                                              value, child) {
                                                            final url =
                                                                value.text;
                                                            if (url.isEmpty) {
                                                              return Container(
                                                                color: Colors
                                                                    .grey
                                                                    .shade900,
                                                                child:
                                                                    const Center(
                                                                  child: Icon(
                                                                    Icons.image,
                                                                    color: Colors
                                                                        .white24,
                                                                    size: 48,
                                                                  ),
                                                                ),
                                                              );
                                                            }

                                                            // Check for video extensions
                                                            final isVideo = url
                                                                    .toLowerCase()
                                                                    .contains(
                                                                      '.mp4',
                                                                    ) ||
                                                                url
                                                                    .toLowerCase()
                                                                    .contains(
                                                                      '.mov',
                                                                    ) ||
                                                                url
                                                                    .toLowerCase()
                                                                    .contains(
                                                                      '.webm',
                                                                    ) ||
                                                                url
                                                                    .toLowerCase()
                                                                    .contains(
                                                                      '.mpeg4',
                                                                    );

                                                            final isPdf = url
                                                                .toLowerCase()
                                                                .contains(
                                                                  '.pdf',
                                                                );
                                                            final isDoc = url
                                                                    .toLowerCase()
                                                                    .contains(
                                                                      '.ppt',
                                                                    ) ||
                                                                url
                                                                    .toLowerCase()
                                                                    .contains(
                                                                      '.pptx',
                                                                    ) ||
                                                                url
                                                                    .toLowerCase()
                                                                    .contains(
                                                                      '.doc',
                                                                    ) ||
                                                                url
                                                                    .toLowerCase()
                                                                    .contains(
                                                                      '.docx',
                                                                    );

                                                            if (isVideo) {
                                                              if (kIsWeb) {
                                                                // Use a stable ID based on URL only, so typing duration doesn't reload video
                                                                final viewId =
                                                                    'remote-video-${url.hashCode}';
                                                                // ignore: undefined_prefixed_name
                                                                ui_web
                                                                    .platformViewRegistry
                                                                    .registerViewFactory(
                                                                        viewId,
                                                                        (
                                                                  int viewId,
                                                                ) {
                                                                  final video = html
                                                                      .VideoElement()
                                                                    ..src = url
                                                                    ..autoplay =
                                                                        true
                                                                    ..loop =
                                                                        true
                                                                    ..muted =
                                                                        false // User requested sound
                                                                    ..controls =
                                                                        true // Allow user to control playback
                                                                    ..style.objectFit =
                                                                        'cover'
                                                                    ..style.width =
                                                                        '100%'
                                                                    ..style.height =
                                                                        '100%';

                                                                  // Apply duration limit dynamically
                                                                  video
                                                                      .onTimeUpdate
                                                                      .listen((
                                                                    event,
                                                                  ) {
                                                                    final durationStr =
                                                                        _durationController
                                                                            .text;
                                                                    final durationLimit =
                                                                        int.tryParse(
                                                                      durationStr,
                                                                    );
                                                                    if (durationLimit !=
                                                                            null &&
                                                                        durationLimit >
                                                                            0) {
                                                                      if (video
                                                                              .currentTime >
                                                                          durationLimit) {
                                                                        video.currentTime =
                                                                            0;
                                                                        video
                                                                            .play();
                                                                      }
                                                                    }
                                                                  });
                                                                  return video;
                                                                });
                                                                return HtmlElementView(
                                                                  viewType:
                                                                      viewId,
                                                                );
                                                              }
                                                              return Container(
                                                                color: Colors
                                                                    .black,
                                                                child: Center(
                                                                  child: Column(
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .center,
                                                                    children: [
                                                                      const Icon(
                                                                        Icons
                                                                            .videocam,
                                                                        color: Colors
                                                                            .white54,
                                                                        size:
                                                                            48,
                                                                      ),
                                                                      const SizedBox(
                                                                        height:
                                                                            8,
                                                                      ),
                                                                      const Text(
                                                                        'Video Background Set',
                                                                        style:
                                                                            TextStyle(
                                                                          color:
                                                                              Colors.white70,
                                                                          fontSize:
                                                                              12,
                                                                        ),
                                                                      ),
                                                                      Padding(
                                                                        padding:
                                                                            const EdgeInsets.all(
                                                                          8.0,
                                                                        ),
                                                                        child:
                                                                            Text(
                                                                          url
                                                                              .split(
                                                                                '/',
                                                                              )
                                                                              .last
                                                                              .split(
                                                                                '?',
                                                                              )
                                                                              .first, // Show filename
                                                                          style:
                                                                              const TextStyle(
                                                                            color:
                                                                                Colors.white30,
                                                                            fontSize:
                                                                                10,
                                                                          ),
                                                                          textAlign:
                                                                              TextAlign.center,
                                                                          maxLines:
                                                                              1,
                                                                          overflow:
                                                                              TextOverflow.ellipsis,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              );
                                                            } else if (isPdf) {
                                                              if (kIsWeb) {
                                                                final viewId =
                                                                    'remote-pdf-${url.hashCode}';
                                                                // ignore: undefined_prefixed_name
                                                                ui_web
                                                                    .platformViewRegistry
                                                                    .registerViewFactory(
                                                                        viewId,
                                                                        (
                                                                  int viewId,
                                                                ) {
                                                                  final element = html
                                                                      .ObjectElement()
                                                                    ..data = url
                                                                    ..type =
                                                                        'application/pdf'
                                                                    ..style.border =
                                                                        'none'
                                                                    ..style.width =
                                                                        '100%'
                                                                    ..style.height =
                                                                        '100%';
                                                                  return element;
                                                                });
                                                                return Stack(
                                                                  children: [
                                                                    HtmlElementView(
                                                                      viewType:
                                                                          viewId,
                                                                    ),
                                                                    Positioned(
                                                                      top: 8,
                                                                      right: 8,
                                                                      child:
                                                                          IconButton(
                                                                        icon:
                                                                            const Icon(
                                                                          Icons
                                                                              .open_in_new,
                                                                          color:
                                                                              Colors.black,
                                                                        ),
                                                                        tooltip:
                                                                            'Open PDF in New Tab',
                                                                        onPressed:
                                                                            () =>
                                                                                launchUrl(
                                                                          Uri.parse(
                                                                            url,
                                                                          ),
                                                                        ),
                                                                        style: IconButton
                                                                            .styleFrom(
                                                                          backgroundColor: Colors
                                                                              .white
                                                                              .withOpacity(
                                                                            0.7,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                );
                                                              }
                                                              return const Center(
                                                                child: Icon(
                                                                  Icons
                                                                      .picture_as_pdf,
                                                                  color: Colors
                                                                      .white,
                                                                  size: 48,
                                                                ),
                                                              );
                                                            } else if (isDoc) {
                                                              if (kIsWeb) {
                                                                final viewId =
                                                                    'remote-doc-${url.hashCode}';
                                                                // ignore: undefined_prefixed_name
                                                                ui_web
                                                                    .platformViewRegistry
                                                                    .registerViewFactory(
                                                                        viewId,
                                                                        (
                                                                  int viewId,
                                                                ) {
                                                                  final iframe = html
                                                                      .IFrameElement()
                                                                    ..src =
                                                                        'https://view.officeapps.live.com/op/embed.aspx?src=${Uri.encodeComponent(url)}'
                                                                    ..style.border =
                                                                        'none'
                                                                    ..style.width =
                                                                        '100%'
                                                                    ..style.height =
                                                                        '100%';
                                                                  return iframe;
                                                                });
                                                                return HtmlElementView(
                                                                  viewType:
                                                                      viewId,
                                                                );
                                                              }
                                                              return const Center(
                                                                child: Icon(
                                                                  Icons
                                                                      .description,
                                                                  color: Colors
                                                                      .white,
                                                                  size: 48,
                                                                ),
                                                              );
                                                            }

                                                            return Image
                                                                .network(
                                                              url,
                                                              fit: BoxFit.cover,
                                                              errorBuilder: (_,
                                                                      __,
                                                                      ___) =>
                                                                  Container(
                                                                color: Colors
                                                                    .grey
                                                                    .shade800,
                                                                child:
                                                                    const Center(
                                                                  child: Icon(
                                                                    Icons
                                                                        .broken_image,
                                                                    color: Colors
                                                                        .white24,
                                                                  ),
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                        );
                                                      },
                                                    ),
                                                  ),

                                                  // Gradient Overlay
                                                  Positioned.fill(
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        gradient:
                                                            LinearGradient(
                                                          begin: Alignment
                                                              .topCenter,
                                                          end: Alignment
                                                              .bottomCenter,
                                                          colors: [
                                                            Colors.black
                                                                .withOpacity(
                                                              0.3,
                                                            ),
                                                            Colors.transparent,
                                                            Colors.black
                                                                .withOpacity(
                                                              0.8,
                                                            ),
                                                          ],
                                                          stops: const [
                                                            0.0,
                                                            0.5,
                                                            1.0,
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),

                                                  // Time Badge (Top Right)
                                                  if (_selectedSlotId != null)
                                                    Positioned(
                                                      top: 20,
                                                      right: 20,
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 12,
                                                          vertical: 6,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.white
                                                              .withOpacity(0.2),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                            20,
                                                          ),
                                                          border: Border.all(
                                                            color: Colors.white
                                                                .withOpacity(
                                                              0.3,
                                                            ),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          _selectedSlotId!,
                                                          style:
                                                              const TextStyle(
                                                            color: Colors.white,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                      ),
                                                    ),

                                                  // Playback preview should not show noticeboard text fields.
                                                  if (_soundUrlController
                                                      .text
                                                      .isNotEmpty)
                                                    Positioned(
                                                      bottom: 40,
                                                      left: 20,
                                                      right: 20,
                                                      child: Row(
                                                        children: [
                                                          const Icon(
                                                            Icons.music_note,
                                                            color:
                                                                Colors.white70,
                                                            size: 16,
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              'Audio attached',
                                                              style: TextStyle(
                                                                color: Colors
                                                                    .white
                                                                    .withOpacity(
                                                                  0.7,
                                                                ),
                                                                fontSize: 12,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // End of Main Expanded
              ],
              // End of Column children
            ),
            // End of Column
          ),
          // End of Padding
        ],
      ),
    );
  }

  Widget _buildNoticeBoardPreview() {
    final timeStr = _selectedSlotId ?? '14:00';
    final intentStr =
        _intentController.text.isNotEmpty ? _intentController.text : 'Intent';
    final titleStr = _titleController.text.isNotEmpty
        ? _titleController.text
        : 'Event Title';
    final descriptionStr = _descriptionController.text;

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background
          if (_noticeBoardBgController.text.isNotEmpty)
            Image.network(
              _noticeBoardBgController.text,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: Colors.grey.shade900),
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.indigo.shade900, Colors.purple.shade900],
                ),
              ),
            ),

          // Overlay
          Container(color: Colors.black.withOpacity(0.4)),

          // Content
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    Text(
                      'National Notice Board',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Next Local Event (Dynamic)
                    _buildNoticeItem(
                      icon: Icons.access_time,
                      label: 'National Event',
                      value: '$timeStr Today',
                    ),
                    const SizedBox(height: 8),

                    // Event Description / Purpose
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titleStr,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (intentStr != 'Intent' &&
                              intentStr.isNotEmpty &&
                              descriptionStr.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2.0),
                              child: Text(
                                intentStr,
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          Text(
                            descriptionStr.isNotEmpty
                                ? descriptionStr
                                : (intentStr != 'Intent' && intentStr.isNotEmpty
                                    ? intentStr
                                    : 'Join us for a moment of shared intention...'),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 11,
                            ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Stats
                    SizedBox(
                      width: double.infinity,
                      child: _buildStatCard(
                        'Participants',
                        '1,234',
                        Icons.people,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: _buildStatCard(
                        'Trending',
                        'Peace',
                        Icons.trending_up,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // National Users Stat
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2.0),
                            child: Icon(
                              Icons.public,
                              color: Colors.lightBlueAccent,
                              size: 14,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '452 National users joined in this moment',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 10,
                                height: 1.2,
                              ),
                              softWrap: true,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeItem({
    required IconData icon,
    required String label,
    required String value,
    String? subValue,
    bool isHighlight = false,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8), // Reduced from 10
          decoration: BoxDecoration(
            color: isHighlight
                ? Colors.amber.withOpacity(0.2)
                : Colors.white.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: isHighlight ? Colors.amber : Colors.white,
            size: 16,
          ), // Reduced from 20
        ),
        const SizedBox(width: 8), // Reduced from 12
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 10,
                ),
              ), // Reduced from 11
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14, // Reduced from 16
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subValue != null)
                Text(
                  subValue,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12,
                  ),
                ), // Reduced from 13
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8), // Reduced from 12
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white70, size: 16), // Reduced from 18
          const SizedBox(height: 4), // Reduced from 6
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16, // Reduced from 18
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 10,
            ),
          ), // Reduced from 11
        ],
      ),
    );
  }

  Map<String, dynamic> _convertEventToMap(Event event) {
    return {
      'id': event.id,
      'title': event.title,
      'intent': event.intent,
      'description': '',
      'visualUrl': event.visualUrl,
      'soundUrl': event.soundUrl,
      'durationSeconds': event.durationSeconds,
      'noticeBoardBgImage': event.noticeBoardBgImage,
      'autoNotify': event.autoNotify,
      'isRecurring': event.isRecurring,
      'isRandomized': event.isRandomized,
      'useTrendingIntent': event.useTrendingIntent,
      'noticeBoardShowBeforeMinutes': event.noticeBoardShowBeforeMinutes,
      'noticeBoardVisibilityAfterMinutes':
          event.noticeBoardVisibilityAfterMinutes,
      'updatedAt': event.updatedAt,
    };
  }
}
