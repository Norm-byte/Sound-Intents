import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/media_item.dart';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
// ignore: deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import '../../models/event.dart';
import '../../services/media_library_service.dart';
import '../../repositories/firestore_event_repository.dart';
import '../widgets/video_widgets.dart';
import '../widgets/web_image.dart';

class EventCreatorTab extends StatefulWidget {
  final DateTime? initialDate;
  final TimeOfDay? initialTime;
  final Event? eventToEdit;
  final Function(Event)? onEventUpdated;

  const EventCreatorTab({
    super.key,
    this.initialDate,
    this.initialTime,
    this.eventToEdit,
    this.onEventUpdated,
  });

  @override
  State<EventCreatorTab> createState() => _EventCreatorTabState();
}

class _EventCreatorTabState extends State<EventCreatorTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final FirestoreEventRepository _eventRepository = FirestoreEventRepository();
  final MediaLibraryService _mediaLibrary = MediaLibraryService();

  // State
  List<Event> _events = [];
  int? _selectedSlotIndex;
  bool _isLoading = false;

  @override
  void didUpdateWidget(EventCreatorTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDate != null &&
        widget.initialDate != oldWidget.initialDate) {
      setState(() {
        _sidebarSelectedDate = widget.initialDate!;
      });
    }
    if (widget.initialTime != null &&
        widget.initialTime != oldWidget.initialTime) {
      _handleInitialTime(widget.initialTime!);
    }
    if (widget.eventToEdit != null &&
        widget.eventToEdit != oldWidget.eventToEdit) {
      _handleEventToEdit(widget.eventToEdit!);
    }
  }

  void _handleEventToEdit(Event event) {
    // Check if event already exists in our list
    final index = _events.indexWhere((e) => e.id == event.id);
    if (index != -1) {
      // Prevent overwriting the fresh data with stale controller values
      // if we are already on this slot.
      if (_selectedSlotIndex == index) {
        _selectedSlotIndex = null;
      }

      // Update the existing slot with the passed event data
      setState(() {
        _events[index] = event;
      });
      _selectSlot(index);
    } else {
      // Add as a new item (temporary or otherwise)
      setState(() {
        _events.add(event);
        _selectSlot(_events.length - 1);
      });
    }
  }

  void _handleInitialTime(TimeOfDay time) {
    // Find if an event exists at this time
    final index = _events.indexWhere((e) {
      if (e.startTimeUTC == null) return false;
      final start = DateTime.parse(e.startTimeUTC!);
      // Check if same day and time (approx)
      return start.year == _sidebarSelectedDate.year &&
          start.month == _sidebarSelectedDate.month &&
          start.day == _sidebarSelectedDate.day &&
          start.hour == time.hour &&
          start.minute == time.minute;
    });

    if (index != -1) {
      _selectSlot(index);
    } else {
      // Create new event at this time
      setState(() {
        final newIndex = _events.length;
        final date = _sidebarSelectedDate;
        final startTime = DateTime.utc(
            date.year, date.month, date.day, time.hour, time.minute);

        _events.add(Event(
          id: 'global_event_$newIndex',
          title: 'New Event',
          startTimeUTC: startTime.toIso8601String(),
          originTime:
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
          isPublished: false,
          isDraft: true,
        ));
        _selectSlot(newIndex);
      });
    }
  }

  // Form Controllers
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _intentController = TextEditingController();
  final TextEditingController _visualUrlController = TextEditingController();
  final TextEditingController _soundUrlController = TextEditingController();
  final TextEditingController _learnMoreContentController =
      TextEditingController();
  final TextEditingController _learnMoreUrlController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  final TextEditingController _noticeBoardBgController =
      TextEditingController();
  final TextEditingController _noticeBoardTextController =
      TextEditingController();
  
  // Notice Board Visibility
  int _noticeBoardVisibilityAfterMinutes = 15; // Default: Keep visible for 15 mins after end
  int _noticeBoardShowBeforeMinutes = 1440; // Default: 24 hours

  // Time Zone State
  String _selectedTimeZoneLabel = 'UTC';
  int _selectedTimeZoneOffset = 0;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 12, minute: 0);
  DateTime _selectedDate = DateTime.now();
  DateTime _sidebarSelectedDate = DateTime.now(); // For the sidebar calendar
  bool _isAutomated = false;
  bool _useTrendingIntent = false;
  String _recurrenceType = 'None'; // 'None', 'Weekly', 'Annually'
  String _selectedEventType = 'global'; // 'global' or 'national'

  // Local Preview State
  Uint8List? _localVisualBytes;
  String? _localVisualName;
  String? _localVideoUrl; // Blob URL for local video preview
  String? _localVideoViewId; // Unique ID for the HtmlElementView

  // Local Learn More Preview State
  Uint8List? _localLearnMoreBytes;
  String? _localLearnMoreName;
  String? _localLearnMoreVideoViewId;

  // Local Learn More Bottom Preview State
  Uint8List? _localLearnMoreBottomBytes;
  String? _localLearnMoreBottomName;
  String? _localLearnMoreBottomVideoViewId;

  // Learn More State
  bool _showLearnMorePreview = false;
  bool _showNoticeBoardPreview = false;
  final FocusNode _learnMoreContentFocus = FocusNode();
  final FocusNode _learnMoreUrlFocus = FocusNode();
  final FocusNode _noticeBoardBgFocus = FocusNode();

  final List<Map<String, dynamic>> _timeZones = [
    {'label': 'UTC', 'offset': 0},
    {'label': 'London (Auto DST)', 'offset': 0},
    {'label': 'Paris (Auto DST)', 'offset': 1},
    {'label': 'New York (Auto DST)', 'offset': -5},
    {'label': 'Los Angeles (Auto DST)', 'offset': -8},
    {'label': 'Tokyo (JST)', 'offset': 9},
    {'label': 'Sydney (Auto DST)', 'offset': 10},
  ];

  @override
  void initState() {
    super.initState();
    _detectLocalTimeZone();
    _loadEvents().then((_) {
      if (mounted && widget.eventToEdit != null) {
        _handleEventToEdit(widget.eventToEdit!);
      }
    });
    _learnMoreContentFocus.addListener(_onFocusChange);
    _learnMoreUrlFocus.addListener(_onFocusChange);
    _noticeBoardBgFocus.addListener(_onFocusChange);
  }

  void _detectLocalTimeZone() {
    try {
      final now = DateTime.now();
      final offset = now.timeZoneOffset.inHours;
      
      // Find a matching timezone in our list
      final match = _timeZones.firstWhere(
        (tz) => tz['offset'] == offset,
        orElse: () => {'label': 'UTC', 'offset': 0},
      );
      
      setState(() {
        _selectedTimeZoneLabel = match['label'];
        _selectedTimeZoneOffset = _offsetForZone(_selectedTimeZoneLabel, now);
      });
    } catch (e) {
      debugPrint('Error detecting timezone: $e');
    }
  }

  String _normalizeTimeZoneLabel(String? rawLabel) {
    final label = (rawLabel ?? 'UTC').trim();
    switch (label) {
      case 'London (GMT)':
      case 'London (BST)':
      case 'London (Auto DST)':
        return 'London (Auto DST)';
      case 'Paris (CET)':
      case 'Paris (CEST)':
      case 'Paris (Auto DST)':
        return 'Paris (Auto DST)';
      case 'New York (EST)':
      case 'New York (EDT)':
      case 'New York (Auto DST)':
        return 'New York (Auto DST)';
      case 'Los Angeles (PST)':
      case 'Los Angeles (PDT)':
      case 'Los Angeles (Auto DST)':
        return 'Los Angeles (Auto DST)';
      case 'Sydney (AEST)':
      case 'Sydney (AEDT)':
      case 'Sydney (Auto DST)':
        return 'Sydney (Auto DST)';
      default:
        return label;
    }
  }

  DateTime _lastSundayOfMonth(int year, int month) {
    final firstOfNextMonth =
        month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    final lastOfMonth = firstOfNextMonth.subtract(const Duration(days: 1));
    return lastOfMonth.subtract(Duration(days: lastOfMonth.weekday % 7));
  }

  DateTime _nthSundayOfMonth(int year, int month, int n) {
    final firstDay = DateTime(year, month, 1);
    final daysUntilSunday = (DateTime.sunday - firstDay.weekday + 7) % 7;
    return firstDay.add(Duration(days: daysUntilSunday + ((n - 1) * 7)));
  }

  bool _isEuropeDst(DateTime date) {
    final start = _lastSundayOfMonth(date.year, 3);
    final end = _lastSundayOfMonth(date.year, 10);
    final d = DateTime(date.year, date.month, date.day);
    return !d.isBefore(start) && d.isBefore(end);
  }

  bool _isUsDst(DateTime date) {
    final start = _nthSundayOfMonth(date.year, 3, 2);
    final end = _nthSundayOfMonth(date.year, 11, 1);
    final d = DateTime(date.year, date.month, date.day);
    return !d.isBefore(start) && d.isBefore(end);
  }

  bool _isSydneyDst(DateTime date) {
    final start = _nthSundayOfMonth(date.year, 10, 1);
    final end = _nthSundayOfMonth(date.year, 4, 1);
    final d = DateTime(date.year, date.month, date.day);

    if (d.month >= 10) {
      return !d.isBefore(start);
    }
    if (d.month <= 4) {
      return d.isBefore(end);
    }
    return false;
  }

  int _offsetForZone(String label, DateTime date) {
    final normalized = _normalizeTimeZoneLabel(label).toLowerCase();

    if (normalized == 'utc') return 0;
    if (normalized.contains('tokyo')) return 9;
    if (normalized.contains('london')) return _isEuropeDst(date) ? 1 : 0;
    if (normalized.contains('paris')) return _isEuropeDst(date) ? 2 : 1;
    if (normalized.contains('new york')) return _isUsDst(date) ? -4 : -5;
    if (normalized.contains('los angeles')) return _isUsDst(date) ? -7 : -8;
    if (normalized.contains('sydney')) return _isSydneyDst(date) ? 11 : 10;

    return 0;
  }

  String _formatDateTime(DateTime dt) {
    return DateFormat('yyyy-MM-dd HH:mm').format(dt);
  }

  void _onFocusChange() {
    if (_learnMoreContentFocus.hasFocus || _learnMoreUrlFocus.hasFocus) {
      setState(() {
        _showLearnMorePreview = true;
        _showNoticeBoardPreview = false;
      });
    } else if (_noticeBoardBgFocus.hasFocus) {
      setState(() {
        _showLearnMorePreview = false;
        _showNoticeBoardPreview = true;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _intentController.dispose();
    _visualUrlController.dispose();
    _soundUrlController.dispose();
    _learnMoreContentController.dispose();
    _learnMoreUrlController.dispose();
    _learnMoreContentFocus.dispose();
    _learnMoreUrlFocus.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // Add timeout to prevent hanging
      final loaded = await _eventRepository.loadGlobalEvents().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('Loading events timed out');
          return [];
        },
      );

      if (!mounted) return;

      if (loaded.isEmpty) {
        // Initialize 7 empty slots
        _events = List.generate(
            7,
            (index) => Event(
                  id: 'global_event_$index',
                  title: 'Global Event ${index + 1}',
                  isPublished: false,
                  isDraft: true,
                ));
      } else {
        // Ensure we have slots for all existing global events + padding to at least 7
        // Do NOT auto-reset expired events. Keep them visible so user knows the slot is occupied (or can republish).
        
        // 1. Map existing events
        final Map<String, Event> idMap = {for (var e in loaded) e.id: e};
        
        // 2. Find max slot index used
        int maxIndex = 6; // Minimum 7 slots (0-6)
        for (var e in loaded) {
           if (e.id.startsWith('global_event_')) {
              try {
                 int idx = int.parse(e.id.split('_').last);
                 if (idx > maxIndex) maxIndex = idx;
              } catch (_) {}
           }
        }
        
        // 3. Generate list covering all slots
        _events = List.generate(maxIndex + 1, (index) {
          final id = 'global_event_$index';
          if (idMap.containsKey(id)) {
             return idMap[id]!;
          }
          // Empty slot
          return Event(
                id: id,
                title: 'Global Event ${index + 1}',
                isPublished: false,
                isDraft: true);
        });

        // 4. Append any events with non-standard IDs (safekeeping)
        for (var e in loaded) {
           if (!e.id.startsWith('global_event_')) {
              _events.add(e);
           }
        }
      }
    } catch (e) {
      debugPrint('Error loading global events: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _selectSlot(int index) {
    if (_selectedSlotIndex != null) {
      _saveCurrentSlotInMemory();
    }

    setState(() {
      _selectedSlotIndex = index;
      final event = _events[index];

      _titleController.text = event.title;
      _intentController.text = event.intent ?? '';
      _visualUrlController.text = event.visualUrl ?? '';
      _soundUrlController.text = event.soundUrl ?? '';
      _learnMoreContentController.text = event.learnMoreContent ?? '';
      _learnMoreUrlController.text = event.learnMoreYoutubeUrl ??
          ''; // Using youtube url field for generic link for now
      _durationController.text = event.durationSeconds?.toString() ?? '';
      _noticeBoardBgController.text = event.noticeBoardBgImage ?? '';
      _noticeBoardTextController.text = event.noticeBoardText ?? '';
      _noticeBoardVisibilityAfterMinutes = event.noticeBoardVisibilityAfterMinutes ?? 0;
      _noticeBoardShowBeforeMinutes = event.noticeBoardShowBeforeMinutes ?? 1440;
      _useTrendingIntent = event.useTrendingIntent ?? false;

      // Parse Time & Zone
      _selectedTimeZoneLabel = _normalizeTimeZoneLabel(event.originTimeZone);

      if (event.originTime != null) {
        final parts = event.originTime!.split(':');
        if (parts.length == 2) {
          _selectedTime =
              TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
      } else if (event.startTimeUTC != null) {
        // Fallback: Use startTimeUTC components as the wall clock time
        // (Since we store wall clock time in UTC slots for global events)
        // BUT we need to convert it back to "Origin Time" by adding the offset
        final dt = DateTime.parse(event.startTimeUTC!);
        final originOffset = _offsetForZone(_selectedTimeZoneLabel, dt);
        final originDt = dt.add(Duration(hours: originOffset));
        _selectedTime = TimeOfDay(hour: originDt.hour, minute: originDt.minute);
      } else {
        _selectedTime = const TimeOfDay(hour: 12, minute: 0);
      }

      if (event.startTimeUTC != null) {
        try {
          _selectedDate = DateTime.parse(event.startTimeUTC!);
        } catch (_) {
          _selectedDate = DateTime.now();
        }
      } else {
        _selectedDate = DateTime.now();
      }

      _selectedTimeZoneOffset =
          _offsetForZone(_selectedTimeZoneLabel, _selectedDate);
      
      // Ensure we are using the correct date for the calendar sidebar too
      _sidebarSelectedDate = _selectedDate;

      _isAutomated = event.isAutomated;
      _recurrenceType = event.recurrenceType ?? 'None';
      _selectedEventType = event.type ?? 'global'; // Load event type

      _localVisualBytes = null;
      _localVisualName = null;
      _localVideoUrl = null;
      _localVideoViewId = null;
    });
  }

  void _saveCurrentSlotInMemory() {
    if (_selectedSlotIndex == null) return;

    final index = _selectedSlotIndex!;
    final current = _events[index];

    // Calculate UTC
    final date = _selectedDate;
    
    // STRICT RULE: All events start at 00 seconds.
    // User requested to remove the "Current Seconds" logic and enforce standard scheduling.
    
    final effectiveOffset = _offsetForZone(_selectedTimeZoneLabel, date);
    final localDateTime = DateTime.utc(
      date.year,
      date.month,
      date.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    final utcDateTime =
      localDateTime.subtract(Duration(hours: effectiveOffset));

    final updated = current.copyWith(
      title: _titleController.text,
      intent: _intentController.text,
      visualUrl: _visualUrlController.text,
      soundUrl: _soundUrlController.text,
      learnMoreContent: _learnMoreContentController.text,
      learnMoreYoutubeUrl: _learnMoreUrlController.text,
      originTimeZone: _selectedTimeZoneLabel,
      originTime:
          '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}',
      startTimeUTC: utcDateTime.toIso8601String(),
      durationSeconds: int.tryParse(_durationController.text),
      noticeBoardBgImage: _noticeBoardBgController.text,
      noticeBoardText: _noticeBoardTextController.text,
      noticeBoardVisibilityAfterMinutes: _noticeBoardVisibilityAfterMinutes,
      noticeBoardShowBeforeMinutes: _noticeBoardShowBeforeMinutes,
      isAutomated: _isAutomated,
      useTrendingIntent: _useTrendingIntent,
      recurrenceType: _recurrenceType,
      type: _selectedEventType,
    );

    setState(() {
      _events[index] = updated;
      // Force a resort or refresh if needed, though setState should rebuild the list
    });
  }

  Future<void> _saveAll() async {
    // Deprecated: Saving individually now
  }

  Future<void> _saveCurrentEvent() async {
    if (_selectedSlotIndex == null) return;
    _saveCurrentSlotInMemory(); // Ensure current edits are applied
    setState(() => _isLoading = true);
    try {
      await _eventRepository.saveGlobalEvent(_events[_selectedSlotIndex!]);
      if (widget.onEventUpdated != null) {
        widget.onEventUpdated!(_events[_selectedSlotIndex!]);
      }
      // No snackbar here, handled by button
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error saving event: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _clearSlot() async {
    if (_selectedSlotIndex == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Slot'),
        content: const Text(
            'Are you sure you want to clear this slot? This will remove all content and reset it to a draft state.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final index = _selectedSlotIndex!;
      final current = _events[index];
      
      // Keep ID and time, reset everything else
      final clearedEvent = Event(
        id: current.id,
        title: 'New Event',
        startTimeUTC: current.startTimeUTC,
        originTime: current.originTime,
        originTimeZone: current.originTimeZone,
        isPublished: false,
        isDraft: true,
        type: 'global',
        // All other fields will be null/default
      );

      _events[index] = clearedEvent;
      await _eventRepository.saveGlobalEvent(clearedEvent);
      
      // Update UI
      _selectSlot(index); // Reload controllers with cleared data
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Slot cleared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing slot: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- Media Handling (Simplified from Scheduler) ---
  Future<void> _pickFromMediaLibrary(
      {required String typeFilter, required Function(String) onSelect}) async {
    
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
                    Text('Select $typeFilter',
                        style: Theme.of(context).textTheme.titleLarge),
                    
                    // Section Filter - Derived from actual media items for consistency
                    StreamBuilder<List<MediaItem>>(
                      stream: _mediaLibrary.getMediaStream(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const SizedBox();
                        final allItems = snapshot.data!;
                        final sections = allItems.map((e) => e.section).toSet().toList()..sort();
                        
                        return DropdownButton<String>(
                          value: selectedSection,
                          hint: const Text('Select Category'),
                          items: [
                            const DropdownMenuItem(value: 'All', child: Text('All Categories')),
                            ...sections.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                          ],
                          onChanged: (val) => setState(() => selectedSection = val),
                        );
                      },
                    ),

                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: selectedSection == null 
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.category, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('Please select a category from the dropdown above', 
                              style: TextStyle(fontSize: 18, color: Colors.grey)),
                          ],
                        ),
                      )
                    : StreamBuilder<List<MediaItem>>(
                    stream: _mediaLibrary.getMediaStream(section: selectedSection == 'All' ? null : selectedSection),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      final allFiles = snapshot.data ?? [];
                      List<MediaItem> files;

                      if (typeFilter == 'visual') {
                        files = allFiles
                            .where((i) => i.type == 'image' || i.type == 'video' || i.type == 'youtube')
                            .toList();
                      } else if (typeFilter != 'any') {
                        files =
                            allFiles.where((i) => i.type == typeFilter).toList();
                      } else {
                        files = allFiles;
                      }

                      if (files.isEmpty) {
                        return Center(
                            child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.perm_media,
                                size: 48, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(
                                'No ${typeFilter == 'any' ? '' : typeFilter} media found in ${selectedSection == 'All' ? 'library' : selectedSection}.'),
                          ],
                        ));
                      }
                      return GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.0,
                        ),
                        itemCount: files.length,
                        itemBuilder: (context, index) {
                          final item = files[index];
                          
                          // Helper to check if it's an image
                          final String lowerName = item.name.toLowerCase();
                          final String lowerUrl = item.url.toLowerCase().split('?').first;
                          
                          bool isRenderableImage = false;
                          String? extension;
                          final renderableExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.wbmp', '.svg'];
                          for (var ext in renderableExtensions) {
                            if (lowerName.endsWith(ext) || lowerUrl.endsWith(ext)) {
                              isRenderableImage = true;
                              extension = ext;
                              break;
                            }
                          }
                          
                          // Robust YouTube detection
                          final isYoutube = item.type == 'youtube' || 
                                          lowerUrl.contains('youtube') || 
                                          lowerUrl.contains('youtu.be');
                                          
                          final isVideo = item.type == 'video' || isYoutube || lowerUrl.endsWith('.mp4');
                          
                          // Detect File Type for Rich Preview
                          if (!isRenderableImage && !isVideo) {
                            if (lowerName.endsWith('.pdf') || lowerUrl.endsWith('.pdf')) extension = '.pdf';
                            else if (lowerName.endsWith('.doc') || lowerUrl.endsWith('.doc') || lowerName.endsWith('.docx') || lowerUrl.endsWith('.docx')) extension = '.doc';
                            else if (lowerName.endsWith('.ppt') || lowerUrl.endsWith('.ppt') || lowerName.endsWith('.pptx') || lowerUrl.endsWith('.pptx')) extension = '.ppt';
                            else if (lowerName.endsWith('.xls') || lowerUrl.endsWith('.xls') || lowerName.endsWith('.xlsx') || lowerUrl.endsWith('.xlsx')) extension = '.xls';
                            else if (lowerName.endsWith('.txt') || lowerUrl.endsWith('.txt')) extension = '.txt';
                          }
                          
                          Widget content;
                          if (isRenderableImage) {
                             // Use WebImage for better cross-origin image support
                            content = WebImage(
                                imageUrl: item.url, 
                                fit: BoxFit.cover,
                            );
                          } else if (isVideo) {
                            // Use VideoGridItem for active preview
                            content = VideoGridItem(
                              url: item.url,
                              type: isYoutube ? 'youtube' : 'upload',
                              enablePreview: true, // Enable preview to show thumbnail
                              autoPlay: false, // Disable autoplay to save resources
                            );
                          } else {
                              // Rich File Type Preview
                              Color fileColor = Colors.grey;
                              IconData fileIcon = Icons.insert_drive_file;
                              String label = extension?.replaceAll('.', '').toUpperCase() ?? item.type.toUpperCase();
                              
                              if (extension == '.pdf') {
                                fileColor = Colors.red.shade400;
                                fileIcon = Icons.picture_as_pdf;
                              } else if (extension == '.doc') {
                                fileColor = Colors.blue.shade600;
                                fileIcon = Icons.description;
                              } else if (extension == '.ppt') {
                                fileColor = Colors.orange.shade600;
                                fileIcon = Icons.slideshow;
                              } else if (extension == '.xls') {
                                fileColor = Colors.green.shade600;
                                fileIcon = Icons.table_chart;
                              } else if (item.type == 'audio') {
                                fileColor = Colors.purple;
                                fileIcon = Icons.audiotrack;
                              }

                              content = Container(
                                color: fileColor.withOpacity(0.15),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(fileIcon, size: 48, color: fileColor),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: fileColor,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        label,
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
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
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: IgnorePointer(
                                      // Ignore pointer on the video widget so the card tap works
                                      child: content,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Text(
                                      item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
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

  Widget _buildCustomCalendar() {
    final monthStart = DateTime(_sidebarSelectedDate.year, _sidebarSelectedDate.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(_sidebarSelectedDate.year, _sidebarSelectedDate.month);
    final firstWeekday = monthStart.weekday; // 1=Mon, 7=Sun
    
    // Header
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() {
                  _sidebarSelectedDate = DateTime(_sidebarSelectedDate.year, _sidebarSelectedDate.month - 1);
                }),
              ),
              Text(
                '${_monthName(_sidebarSelectedDate.month)} ${_sidebarSelectedDate.year}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() {
                  _sidebarSelectedDate = DateTime(_sidebarSelectedDate.year, _sidebarSelectedDate.month + 1);
                }),
              ),
            ],
          ),
        ),
        // Days Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
              .map((d) => Text(d, style: const TextStyle(color: Colors.grey, fontSize: 12)))
              .toList(),
        ),
        const SizedBox(height: 8),
        // Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
          itemCount: daysInMonth + firstWeekday - 1,
          itemBuilder: (context, index) {
            if (index < firstWeekday - 1) return const SizedBox();
            
            final day = index - (firstWeekday - 1) + 1;
            final date = DateTime(_sidebarSelectedDate.year, _sidebarSelectedDate.month, day);
            final isSelected = DateUtils.isSameDay(date, _sidebarSelectedDate);
            final isToday = DateUtils.isSameDay(date, DateTime.now());
            
            // Check for events
            final eventsOnDay = _events.where((e) {
              if (e.startTimeUTC == null) return false;
              final start = DateTime.parse(e.startTimeUTC!);
              return DateUtils.isSameDay(start, date);
            }).toList();
            
            Color? statusColor;
            if (eventsOnDay.isNotEmpty) {
              final hasPublished = eventsOnDay.any((e) => e.isPublished);
              statusColor = hasPublished ? Colors.green : Colors.amber;
            }

            return GestureDetector(
              onTap: () => setState(() => _sidebarSelectedDate = date),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.indigo : (statusColor?.withOpacity(0.2) ?? Colors.transparent),
                  shape: BoxShape.circle,
                  border: isToday ? Border.all(color: Colors.indigo) : null,
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$day',
                      style: TextStyle(
                        color: isSelected ? Colors.white : (statusColor != null ? Colors.black87 : Colors.black),
                        fontWeight: isSelected || statusColor != null ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    if (statusColor != null && !isSelected)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for KeepAlive

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Sidebar: Schedule & Calendar
          Container(
            width: 320, // Slightly wider for calendar
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.grey.shade300)),
              color: Colors.grey.shade50,
            ),
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Schedule',
                          style: Theme.of(context).textTheme.titleLarge),
                      IconButton(
                        icon:
                            const Icon(Icons.add_circle, color: Colors.indigo),
                        tooltip: 'Add Event to Selected Date',
                        onPressed: () {
                          setState(() {
                            final newIndex = _events.length;
                            // Create event for the currently selected sidebar date
                            final date = _sidebarSelectedDate;
                            // Default to 12:00 PM UTC on that date
                            final startTime = DateTime.utc(
                                date.year, date.month, date.day, 12, 0);

                            _events.add(Event(
                              id: 'global_event_$newIndex',
                              title: 'New Event',
                              startTimeUTC: startTime.toIso8601String(),
                              originTime: '12:00',
                              isPublished: false,
                              isDraft: true,
                            ));
                            _selectSlot(newIndex);
                          });
                        },
                      ),
                    ],
                  ),
                ),

                const Divider(),

                // Calendar
                _buildCustomCalendar(),

                const Divider(),

                // Events for Selected Date
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Events for ${_sidebarSelectedDate.day}/${_sidebarSelectedDate.month}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 16),
                        onPressed: _loadEvents,
                        tooltip: 'Refresh List',
                      )
                    ],
                  ),
                ),

                Expanded(
                  child: ListView.builder(
                    itemCount: 96, // 24 hours * 4 slots
                    itemBuilder: (context, index) {
                      final hour = index ~/ 4;
                      final minute = (index % 4) * 15;
                      final timeStr =
                          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

                      // Find event for this slot
                      Event? event;
                      try {
                        event = _events.firstWhere((e) {
                          if (e.startTimeUTC == null) return false;
                          
                          // Robust matching logic
                          // 1. Try to match by Origin Time (User's preferred time)
                          if (e.originTime != null) {
                             final parts = e.originTime!.split(':');
                             if (parts.length == 2) {
                               final eHour = int.parse(parts[0]);
                               final eMinute = int.parse(parts[1]);
                               
                               // Check if this event falls within this 15-minute slot
                               // e.g. Slot 17:45 covers 17:45 to 17:59
                               // So 17:55 should match here.
                               if (eHour == hour && eMinute >= minute && eMinute < minute + 15) {
                                 // Also check date match
                                 final utcDt = DateTime.parse(e.startTimeUTC!);
                                 // We assume the user is viewing the date relevant to the event
                                 // But we must be careful. If the user selects Jan 2, we want events for Jan 2.
                                 // The originTime doesn't have a date.
                                 // Let's check if the UTC date is "close" to the selected date.
                                 // Or better, convert UTC to the "Origin Timezone" if we knew it.
                                 // Since we don't easily know the offset here without parsing, 
                                 // let's rely on the fact that the user likely created it for this date.
                                 // A simple check: is the UTC day same as selected day? 
                                 // (This might fail for edge cases near midnight UTC, but it's a start)
                                 
                                 // BETTER: Check if the event's UTC time falls within the 24h window of the selected date
                                 // But we don't know the timezone offset of the viewer vs the event creator.
                                 
                                 // Let's stick to: If the UTC date matches the selected date, show it.
                                 return utcDt.year == _sidebarSelectedDate.year &&
                                        utcDt.month == _sidebarSelectedDate.month &&
                                        utcDt.day == _sidebarSelectedDate.day;
                               }
                             }
                          }

                          // 2. Fallback: Match by UTC time converted to Local (Admin's local)
                          // This assumes the Admin is viewing in their local time
                          final dt = DateTime.parse(e.startTimeUTC!).toLocal();
                          return dt.year == _sidebarSelectedDate.year &&
                              dt.month == _sidebarSelectedDate.month &&
                              dt.day == _sidebarSelectedDate.day &&
                              dt.hour == hour &&
                              dt.minute >= minute &&
                              dt.minute < minute + 15;
                        });
                      } catch (_) {}

                      if (event != null) {
                        final originalIndex = _events.indexOf(event);
                        final isSelected = _selectedSlotIndex == originalIndex;
                        
                        // Check if event is in the past
                        bool isPast = false;
                        if (event.startTimeUTC != null) {
                          final dt = DateTime.parse(event.startTimeUTC!);
                          final duration = Duration(minutes: event.durationSeconds != null ? (event.durationSeconds! ~/ 60) : 60);
                          isPast = dt.add(duration).isBefore(DateTime.now().toUtc());
                        }

                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          elevation: isSelected ? 4 : 1,
                          color: isSelected
                              ? Theme.of(context).primaryColor.withOpacity(0.1)
                              : null,
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 0),
                            title: Text(event.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12)),
                            leading: CircleAvatar(
                              radius: 10,
                              backgroundColor: isSelected
                                  ? Theme.of(context).primaryColor
                                  : (isPast ? Colors.amber : Colors.green),
                              child: const Icon(Icons.event,
                                  color: Colors.white, size: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(event.originTime ?? timeStr,
                                    style: const TextStyle(fontSize: 10)),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Delete Event?'),
                                        content: Text('Are you sure you want to delete "${event!.title}"?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, true),
                                            child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                    
                                    if (confirm == true) {
                                      setState(() => _isLoading = true);
                                      try {
                                        await _eventRepository.deleteGlobalEvent(event!.id);
                                        setState(() {
                                          _events.remove(event);
                                          if (_selectedSlotIndex == originalIndex) {
                                            _selectedSlotIndex = null;
                                          } else if (_selectedSlotIndex != null && _selectedSlotIndex! > originalIndex) {
                                            _selectedSlotIndex = _selectedSlotIndex! - 1;
                                          }
                                        });
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Event deleted')),
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Error deleting event: $e')),
                                          );
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(() => _isLoading = false);
                                        }
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                            onTap: () => _selectSlot(originalIndex),
                          ),
                        );
                      } else {
                        // Empty Slot
                        return InkWell(
                          onTap: () {
                            // Create new event at this time
                            setState(() {
                              final newIndex = _events.length;
                              final date = _sidebarSelectedDate;
                              final startTime = DateTime.utc(date.year,
                                  date.month, date.day, hour, minute);

                              _events.add(Event(
                                id: 'global_event_$newIndex',
                                title: 'New Event',
                                startTimeUTC: startTime.toIso8601String(),
                                originTime: timeStr,
                                isPublished: false,
                                isDraft: true,
                              ));
                              _selectSlot(newIndex);
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 6, // Small dot
                                  backgroundColor: Colors.red.withOpacity(0.3),
                                ),
                                const SizedBox(width: 12),
                                Text(timeStr,
                                    style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 11)),
                                const SizedBox(width: 8),
                                Text('Empty',
                                    style: TextStyle(
                                        color: Colors.grey.shade300,
                                        fontSize: 11)),
                              ],
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          // Right Area: Editor
          Expanded(
            flex: 1,
            child: _selectedSlotIndex == null
                ? const Center(child: Text('Select an event slot to edit'))
                : _buildEditor(),
          ),

          const SizedBox(width: 16),

          // Far Right: Phone Preview
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
                    child: Text('Device Preview',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.grey)),
                  ),
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio:
                            9 / 19.5, // Typical modern phone aspect ratio
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.black, width: 8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              )
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: _showNoticeBoardPreview
                                ? _buildNoticeBoardPreview()
                                : (_showLearnMorePreview
                                    ? _buildLearnMorePreview()
                                    : _buildEventPreview()),
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
    );
  }

  Widget _buildNoticeBoardPreview() {
    // Calculate Local Time for Preview
    final date = _selectedDate;
    final originDateTime = DateTime.utc(date.year, date.month, date.day,
        _selectedTime.hour, _selectedTime.minute);
    final utcDateTime =
        originDateTime.subtract(Duration(hours: _selectedTimeZoneOffset));
    final localDateTime = utcDateTime.toLocal();
    final timeStr =
        '${localDateTime.hour.toString().padLeft(2, '0')}:${localDateTime.minute.toString().padLeft(2, '0')}';

    final intentStr =
        _intentController.text.isNotEmpty ? _intentController.text : 'Intent';
    final titleStr = _titleController.text.isNotEmpty
        ? _titleController.text
        : 'Event Title';
    final descriptionStr = _noticeBoardTextController.text;

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background
          Positioned.fill(
            child: _noticeBoardBgController.text.isNotEmpty
                ? Image.network(
                    _noticeBoardBgController.text,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: Colors.grey.shade900),
                  )
                : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.indigo.shade900,
                          Colors.purple.shade900
                        ],
                      ),
                    ),
                  ),
          ),

          // Overlay
          Positioned.fill(
              child: Container(color: Colors.black.withOpacity(0.4))),

          // Content
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40),
                    Text(
                      'Notice Board',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Worldwide Event (Dynamic)
                    _buildNoticeItem(
                      icon: Icons.public,
                      label: 'Worldwide Event',
                      value: '$timeStr Today',
                    ),
                    const SizedBox(height: 16),

                    // Event Description / Purpose
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titleStr,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          if (intentStr != 'Intent' && intentStr.isNotEmpty && descriptionStr.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4.0),
                              child: Text(
                                intentStr,
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          Text(
                            descriptionStr.isNotEmpty
                                ? descriptionStr
                                : (intentStr != 'Intent' && intentStr.isNotEmpty ? intentStr : 'Join us for a moment of shared intention...'),
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Stats
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                              'Participants', '1,234', Icons.people),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                              'Trending', 'Peace', Icons.trending_up),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // National Users Stat
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.public,
                              color: Colors.lightBlueAccent, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '452 National users joined in the international worldwide event',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    // Action Buttons (Visual Only)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {}, // Visual only
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withOpacity(0.15),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              side: BorderSide(
                                  color: Colors.white.withOpacity(0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Learn More'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {}, // Visual only
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.black87,
                              elevation: 2,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Join In',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
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
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isHighlight
                ? Colors.amber.withOpacity(0.2)
                : Colors.white.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon,
              color: isHighlight ? Colors.amber : Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.7), fontSize: 11)),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              if (subValue != null)
                Text(subValue,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.9), fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.6), fontSize: 11)),
        ],
      ),
    );
  }

  void _showExpandedContent(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(24),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 800,
              height: 450,
              child: _buildExpandedMedia(url),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedMedia(String url) {
    // 1. YouTube
    final youtubeId = _extractYoutubeId(url);
    if (youtubeId.isNotEmpty) {
      if (kIsWeb) {
        final viewId =
            'youtube-expanded-$youtubeId-${DateTime.now().millisecondsSinceEpoch}';
        // ignore: undefined_prefixed_name
        ui_web.platformViewRegistry.registerViewFactory(viewId, (int viewId) {
          final iframe = html.IFrameElement()
            ..src = 'https://www.youtube.com/embed/$youtubeId?autoplay=1'
            ..style.border = 'none'
            ..allow = 'autoplay; encrypted-media; picture-in-picture';
          return iframe;
        });
        return HtmlElementView(viewType: viewId);
      }
    }

    // 2. Video
    final isVideo = url.toLowerCase().contains('.mp4') ||
        url.toLowerCase().contains('.mov') ||
        url.toLowerCase().contains('.webm') ||
        url.toLowerCase().contains('.mpeg4');

    if (isVideo) {
      if (kIsWeb) {
        final viewId =
            'video-expanded-${url.hashCode}-${DateTime.now().millisecondsSinceEpoch}';
        // ignore: undefined_prefixed_name
        ui_web.platformViewRegistry.registerViewFactory(viewId, (int viewId) {
          final video = html.VideoElement()
            ..src = url
            ..autoplay = true
            ..loop = false
            ..controls = true
            ..style.objectFit = 'contain'
            ..style.width = '100%'
            ..style.height = '100%';
          return video;
        });
        return HtmlElementView(viewType: viewId);
      }
    }

    // 3. Image
    return Image.network(
      url,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          const Center(child: Icon(Icons.broken_image, color: Colors.white)),
    );
  }

  Widget _buildLearnMorePreview() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Row(
              children: [
                const Icon(Icons.arrow_back, color: Colors.black),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _titleController.text.isEmpty
                        ? 'Event Title'
                        : _titleController.text,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content (3/4) - Visual Only
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.black,
              child: Builder(
                builder: (context) {
                  // 1. Check Local Preview
                  if (_localLearnMoreBytes != null) {
                    final name = _localLearnMoreName?.toLowerCase() ?? '';
                    final isVideo = name.endsWith('.mp4') ||
                        name.endsWith('.mov') ||
                        name.endsWith('.webm') ||
                        name.endsWith('.mpeg') ||
                        name.endsWith('.mpg') ||
                        name.endsWith('.avi') ||
                        name.endsWith('.mkv') ||
                        name.endsWith('.wmv');
                    final isPdf = name.endsWith('.pdf');
                    final isDoc = name.endsWith('.ppt') ||
                        name.endsWith('.pptx') ||
                        name.endsWith('.doc') ||
                        name.endsWith('.docx');

                    if (isVideo) {
                      if (kIsWeb && _localLearnMoreVideoViewId != null) {
                        return HtmlElementView(
                            viewType: _localLearnMoreVideoViewId!);
                      }
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.videocam,
                                color: Colors.white54, size: 48),
                            SizedBox(height: 8),
                            Text('Video Selected',
                                style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                      );
                    } else if (isPdf) {
                      if (kIsWeb && _localLearnMoreVideoViewId != null) {
                        return HtmlElementView(
                            viewType: _localLearnMoreVideoViewId!);
                      }
                      return const Center(
                          child: Icon(Icons.picture_as_pdf,
                              color: Colors.white, size: 48));
                    } else if (isDoc) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.description,
                                color: Colors.white54, size: 48),
                            SizedBox(height: 8),
                            Text('Document Selected',
                                style: TextStyle(color: Colors.white70)),
                            Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(
                                'Preview will be available after upload completes.',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 10),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return Image.memory(
                      _localLearnMoreBytes!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image, color: Colors.white)),
                    );
                  }

                  // 2. Check URL
                  final url = _learnMoreContentController.text;
                  if (url.isNotEmpty) {
                    final isVideo = url.toLowerCase().contains('.mp4') ||
                        url.toLowerCase().contains('.mov') ||
                        url.toLowerCase().contains('.webm') ||
                        url.toLowerCase().contains('.mpeg') ||
                        url.toLowerCase().contains('.mpg') ||
                        url.toLowerCase().contains('.avi') ||
                        url.toLowerCase().contains('.mkv');
                    final isPdf = url.toLowerCase().contains('.pdf');
                    final isDoc = url.toLowerCase().contains('.ppt') ||
                        url.toLowerCase().contains('.pptx') ||
                        url.toLowerCase().contains('.doc') ||
                        url.toLowerCase().contains('.docx');

                    if (isVideo) {
                      if (kIsWeb) {
                        final viewId =
                            'learn-more-main-video-${url.hashCode}-${DateTime.now().millisecondsSinceEpoch}';
                        // ignore: undefined_prefixed_name
                        ui_web.platformViewRegistry.registerViewFactory(viewId,
                            (int viewId) {
                          final video = html.VideoElement()
                            ..src = url
                            ..autoplay = false
                            ..loop = false
                            ..controls = true
                            ..style.objectFit =
                                'contain' // Changed to contain to ensure full video is seen
                            ..style.width = '100%'
                            ..style.height = '100%';
                          video.setAttribute('playsinline', 'true');
                          return video;
                        });
                        return Stack(
                          children: [
                            HtmlElementView(
                                viewType: viewId, key: ValueKey(viewId)),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: IconButton(
                                icon: const Icon(Icons.open_in_new,
                                    color: Colors.white),
                                tooltip: 'Open Video in New Tab',
                                onPressed: () => launchUrl(Uri.parse(url)),
                              ),
                            ),
                          ],
                        );
                      }
                      return const Center(
                          child: Icon(Icons.videocam, color: Colors.white));
                    } else if (isPdf) {
                      if (kIsWeb) {
                        final viewId = 'learn-more-main-pdf-${url.hashCode}';
                        // ignore: undefined_prefixed_name
                        ui_web.platformViewRegistry.registerViewFactory(viewId,
                            (int viewId) {
                          final element = html.IFrameElement()
                            ..src = '$url#toolbar=0&navpanes=0&scrollbar=0&view=FitH'
                            ..style.border = 'none'
                            ..style.width = '100%'
                            ..style.height = '100%'
                            ..style.display = 'block'
                            ..style.overflowX = 'hidden'; // Prevent minor horizontal scrolling
                          return element;
                        });
                        return Stack(
                          children: [
                            HtmlElementView(viewType: viewId),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: IconButton(
                                icon: const Icon(Icons.open_in_new,
                                    color: Colors.black),
                                tooltip: 'Open PDF in New Tab',
                                onPressed: () => launchUrl(Uri.parse(url)),
                                style: IconButton.styleFrom(
                                    backgroundColor:
                                        Colors.white.withOpacity(0.7)),
                              ),
                            ),
                          ],
                        );
                      }
                      return const Center(
                          child:
                              Icon(Icons.picture_as_pdf, color: Colors.white));
                    } else if (isDoc) {
                      if (kIsWeb) {
                        final viewId = 'learn-more-main-doc-${url.hashCode}';
                        // ignore: undefined_prefixed_name
                        ui_web.platformViewRegistry.registerViewFactory(viewId,
                            (int viewId) {
                          final iframe = html.IFrameElement()
                            ..src =
                                'https://view.officeapps.live.com/op/embed.aspx?src=${Uri.encodeComponent(url)}'
                            ..style.border = 'none'
                            ..style.width = '100%'
                            ..style.height = '100%';
                          return iframe;
                        });
                        return HtmlElementView(viewType: viewId);
                      }
                      return const Center(
                          child: Icon(Icons.description, color: Colors.white));
                    }

                    return Image.network(
                      url,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                            color: Colors.white,
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image, color: Colors.white)),
                    );
                  }

                  // 3. Placeholder
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image, color: Colors.white24, size: 48),
                        SizedBox(height: 8),
                        Text('No Learn More Visual',
                            style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          // YouTube Thumbnail / Secondary Content (1/4)
          if (_learnMoreUrlController.text.isNotEmpty ||
              _localLearnMoreBottomBytes != null)
            Expanded(
              flex: 1,
              child: GestureDetector(
                onTap: () {
                  if (_learnMoreUrlController.text.isNotEmpty) {
                    _showExpandedContent(_learnMoreUrlController.text);
                  }
                },
                child: Container(
                  color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Builder(
                        builder: (context) {
                          // 0. Check Local Preview
                          if (_localLearnMoreBottomBytes != null) {
                            final name =
                                _localLearnMoreBottomName?.toLowerCase() ?? '';
                            final isVideo = name.endsWith('.mp4') ||
                                name.endsWith('.mov') ||
                                name.endsWith('.webm') ||
                                name.endsWith('.mpeg') ||
                                name.endsWith('.mpg') ||
                                name.endsWith('.avi') ||
                                name.endsWith('.mkv');

                            if (isVideo) {
                              if (kIsWeb &&
                                  _localLearnMoreBottomVideoViewId != null) {
                                return HtmlElementView(
                                    viewType:
                                        _localLearnMoreBottomVideoViewId!);
                              }
                              return const Center(
                                  child: Icon(Icons.videocam,
                                      color: Colors.white54));
                            }

                            return Image.memory(
                              _localLearnMoreBottomBytes!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.broken_image,
                                      color: Colors.white)),
                            );
                          }

                          final url = _learnMoreUrlController.text;

                          // 1. Check for YouTube
                          final youtubeId = _extractYoutubeId(url);
                          if (youtubeId.isNotEmpty) {
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  'https://img.youtube.com/vi/$youtubeId/0.jpg',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                      color: Colors.grey.shade900,
                                      child: const Icon(
                                          Icons.play_circle_outline,
                                          color: Colors.white,
                                          size: 48)),
                                ),
                                const Center(
                                    child: Icon(Icons.play_circle_fill,
                                        color: Colors.white, size: 48)),
                              ],
                            );
                          }

                          // 2. Check for Video
                          final isVideo = url.toLowerCase().contains('.mp4') ||
                              url.toLowerCase().contains('.mov') ||
                              url.toLowerCase().contains('.webm') ||
                              url.toLowerCase().contains('.mpeg4');

                          if (isVideo) {
                            if (kIsWeb) {
                              final viewId = 'learn-more-video-${url.hashCode}';
                              // ignore: undefined_prefixed_name
                              ui_web.platformViewRegistry
                                  .registerViewFactory(viewId, (int viewId) {
                                final video = html.VideoElement()
                                  ..src = url
                                  ..autoplay = false
                                  ..loop = false
                                  ..controls =
                                      false // Disable controls in preview to encourage expanding
                                  ..style.objectFit = 'cover'
                                  ..style.width = '100%'
                                  ..style.height = '100%';
                                return video;
                              });
                              return HtmlElementView(viewType: viewId);
                            }
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.videocam,
                                      color: Colors.white54, size: 32),
                                  const SizedBox(height: 4),
                                  const Text('Video Content',
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 10)),
                                ],
                              ),
                            );
                          }

                          // 3. Assume Image
                          return Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade900,
                              child: const Center(
                                  child: Icon(Icons.broken_image,
                                      color: Colors.white24)),
                            ),
                          );
                        },
                      ),

                      // Expand Overlay Icon
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.fullscreen,
                              color: Colors.white, size: 20),
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

  String _extractYoutubeId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    if (uri.host.contains('youtu.be')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    }
    return uri.queryParameters['v'] ?? '';
  }

  Widget _buildEventPreview() {
    return Stack(
      children: [
        // Background Visual
        Positioned.fill(
          child: Builder(
            builder: (context) {
              // 1. Check Local Preview First
              if (_localVisualBytes != null) {
                final name = _localVisualName?.toLowerCase() ?? '';
                final isLocalVideo = name.endsWith('.mp4') ||
                    name.endsWith('.mov') ||
                    name.endsWith('.webm') ||
                    name.endsWith('.mpeg') ||
                    name.endsWith('.mpg') ||
                    name.endsWith('.avi') ||
                    name.endsWith('.mkv') ||
                    name.endsWith('.wmv');
                final isPdf = name.endsWith('.pdf');
                final isDoc = name.endsWith('.ppt') ||
                    name.endsWith('.pptx') ||
                    name.endsWith('.doc') ||
                    name.endsWith('.docx');

                if (isLocalVideo) {
                  if (kIsWeb && _localVideoViewId != null) {
                    return HtmlElementView(viewType: _localVideoViewId!);
                  }
                  // Fallback for non-web or if view ID missing
                  return Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.videocam,
                              color: Colors.white54, size: 48),
                          const SizedBox(height: 8),
                          const Text(
                            'Video Selected',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              _localVisualName ?? 'Unknown',
                              style: const TextStyle(
                                  color: Colors.white30, fontSize: 10),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                } else if (isPdf) {
                  if (kIsWeb && _localVideoViewId != null) {
                    // Reusing _localVideoViewId for PDF view ID
                    return Stack(
                      children: [
                        HtmlElementView(viewType: _localVideoViewId!),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton(
                            icon: const Icon(Icons.open_in_new,
                                color: Colors.black),
                            tooltip: 'Open PDF in New Tab',
                            onPressed: () =>
                                html.window.open(_localVideoUrl!, '_blank'),
                            style: IconButton.styleFrom(
                                backgroundColor: Colors.white.withOpacity(0.7)),
                          ),
                        ),
                      ],
                    );
                  }
                  return const Center(
                      child: Icon(Icons.picture_as_pdf,
                          color: Colors.white, size: 48));
                } else if (isDoc) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.description,
                            color: Colors.white54, size: 48),
                        const SizedBox(height: 8),
                        const Text('Document Selected',
                            style: TextStyle(color: Colors.white70)),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            'Preview will be available after upload completes.',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 10),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  return Image.memory(
                    _localVisualBytes!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade800,
                      child: const Center(
                          child:
                              Icon(Icons.broken_image, color: Colors.white24)),
                    ),
                  );
                }
              }

              // 2. Fallback to URL
              return ValueListenableBuilder<TextEditingValue>(
                valueListenable: _visualUrlController,
                builder: (context, value, child) {
                  final url = value.text;
                  if (url.isEmpty) {
                    return Container(
                      color: Colors.grey.shade900,
                      child: const Center(
                        child:
                            Icon(Icons.image, color: Colors.white24, size: 48),
                      ),
                    );
                  }

                  // Check for video extensions
                  final isVideo = url.toLowerCase().contains('.mp4') ||
                      url.toLowerCase().contains('.mov') ||
                      url.toLowerCase().contains('.webm') ||
                      url.toLowerCase().contains('.mpeg') ||
                      url.toLowerCase().contains('.mpg') ||
                      url.toLowerCase().contains('.avi') ||
                      url.toLowerCase().contains('.mkv');

                  final isPdf = url.toLowerCase().contains('.pdf');
                  final isDoc = url.toLowerCase().contains('.ppt') ||
                      url.toLowerCase().contains('.pptx') ||
                      url.toLowerCase().contains('.doc') ||
                      url.toLowerCase().contains('.docx');

                  if (isVideo) {
                    if (kIsWeb) {
                      final viewId =
                          'creator-remote-video-${url.hashCode}-${_durationController.text}';
                      // ignore: undefined_prefixed_name
                      ui_web.platformViewRegistry.registerViewFactory(viewId,
                          (int viewId) {
                        final video = html.VideoElement()
                          ..src = url
                          ..autoplay = true
                          ..loop = true
                          ..muted = false // User requested sound
                          ..controls = true // Allow user to control playback
                          ..style.objectFit = 'cover'
                          ..style.width = '100%'
                          ..style.height = '100%';

                        // Apply duration limit if set
                        final durationStr = _durationController.text;
                        final durationLimit = int.tryParse(durationStr);
                        if (durationLimit != null && durationLimit > 0) {
                          video.onTimeUpdate.listen((event) {
                            if (video.currentTime > durationLimit) {
                              video.currentTime = 0;
                              video.play();
                            }
                          });
                        }
                        return video;
                      });
                      return HtmlElementView(viewType: viewId);
                    }

                    return Container(
                      color: Colors.black,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.videocam,
                                color: Colors.white54, size: 48),
                            const SizedBox(height: 8),
                            const Text(
                              'Video Background Set',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                url
                                    .split('/')
                                    .last
                                    .split('?')
                                    .first, // Show filename
                                style: const TextStyle(
                                    color: Colors.white30, fontSize: 10),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  } else if (isPdf) {
                    if (kIsWeb) {
                      final viewId = 'creator-remote-pdf-${url.hashCode}';
                      // ignore: undefined_prefixed_name
                      ui_web.platformViewRegistry.registerViewFactory(viewId,
                          (int viewId) {
                        final element = html.IFrameElement()
                          ..src = '$url#toolbar=0&navpanes=0&scrollbar=0&view=FitH'
                          ..style.border = 'none'
                          ..style.width = '100%'
                          ..style.height = '100%'
                          ..style.display = 'block'
                          ..style.overflowX = 'hidden'; // Prevent minor horizontal scrolling
                        return element;
                      });
                      return Stack(
                        children: [
                          HtmlElementView(viewType: viewId),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              icon: const Icon(Icons.open_in_new,
                                  color: Colors.black),
                              tooltip: 'Open PDF in New Tab',
                              onPressed: () => launchUrl(Uri.parse(url)),
                              style: IconButton.styleFrom(
                                  backgroundColor:
                                      Colors.white.withOpacity(0.7)),
                            ),
                          ),
                        ],
                      );
                    }
                    return const Center(
                        child: Icon(Icons.picture_as_pdf,
                            color: Colors.white, size: 48));
                  } else if (isDoc) {
                    if (kIsWeb) {
                      final viewId = 'creator-remote-doc-${url.hashCode}';
                      // ignore: undefined_prefixed_name
                      ui_web.platformViewRegistry.registerViewFactory(viewId,
                          (int viewId) {
                        final iframe = html.IFrameElement()
                          ..src =
                              'https://view.officeapps.live.com/op/embed.aspx?src=${Uri.encodeComponent(url)}'
                          ..style.border = 'none'
                          ..style.width = '100%'
                          ..style.height = '100%';
                        return iframe;
                      });
                      return HtmlElementView(viewType: viewId);
                    }
                    return const Center(
                        child: Icon(Icons.description,
                            color: Colors.white, size: 48));
                  }

                  return Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade800,
                      child: const Center(
                          child:
                              Icon(Icons.broken_image, color: Colors.white24)),
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
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.3),
                  Colors.transparent,
                  Colors.black.withOpacity(0.8),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),


      ],
    );
  }

  Widget _buildEditor() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      'Editing: ${_events[_selectedSlotIndex!].title}',
                      style: Theme.of(context).textTheme.headlineSmall,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _events[_selectedSlotIndex!].isPublished
                          ? Colors.green.shade100
                          : Colors.amber.shade100,
                      border: Border.all(
                        color: _events[_selectedSlotIndex!].isPublished
                            ? Colors.green
                            : Colors.amber,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _events[_selectedSlotIndex!].isPublished
                          ? 'PUBLISHED'
                          : 'DRAFT',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _events[_selectedSlotIndex!].isPublished
                            ? Colors.green.shade900
                            : Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _clearSlot,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear Slot'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade900,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            // User request: Default to draft (not published)
                            setState(() {
                              _saveCurrentSlotInMemory();
                              if (_selectedSlotIndex != null) {
                                _events[_selectedSlotIndex!] =
                                    _events[_selectedSlotIndex!].copyWith(
                                  isPublished: false, // Default to draft
                                  isDraft: true,
                                );
                              }
                            });
                            await _saveCurrentEvent();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Event Saved to Dashboard (Draft)'),
                                    backgroundColor: Colors.amber),
                              );
                            }
                          },
                    icon: const Icon(Icons.dashboard_customize),
                    label: const Text('Save to Dashboard'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade800,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            // Publish event (make it visible to users)
                            setState(() {
                              _saveCurrentSlotInMemory();
                              if (_selectedSlotIndex != null) {
                                _events[_selectedSlotIndex!] =
                                    _events[_selectedSlotIndex!].copyWith(
                                  isPublished: true, // PUBLISH
                                  isDraft: false,
                                );
                              }
                            });
                            await _saveCurrentEvent();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Event Published! Now visible to users'),
                                    backgroundColor: Colors.green),
                              );
                            }
                          },
                    icon: const Icon(Icons.publish),
                    label: const Text('Publish Event'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  // Always show the reset button if something goes wrong, not just when loading
                  // This is a safety hatch for the user
                  IconButton(
                    icon: Icon(Icons.refresh,
                        color: _isLoading ? Colors.red : Colors.grey),
                    tooltip: 'Force Reset Loading State',
                    onPressed: () {
                      setState(() => _isLoading = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Loading state reset manually')),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // --- Event Type & Timing Section ---
          Listener(
            onPointerDown: (_) => setState(() => _showLearnMorePreview = false),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Type & Timing',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    // Event Type Selector
                    Row(
                      children: [
                         Expanded(
                           child: DropdownButtonFormField<String>(
                             isExpanded: true,
                             initialValue: _recurrenceType == 'None' || _recurrenceType == 'Daily' || _recurrenceType == 'Weekly' ? 'global' : 'global', // Temporary, we need a separate field for type in the state
                             // Actually, let's just use a SegmentedButton or Radio buttons for Type
                             // But we need to add _selectedEventType field to state first.
                             // For now, let's hack it in by hijacking the UI structure
                             decoration: const InputDecoration(labelText: 'Event Type'),
                             items: const [
                               DropdownMenuItem(value: 'global', child: Text('Global (Synchronized Worldwide)')),
                               DropdownMenuItem(value: 'national', child: Text('National (Local Time)')),
                             ],
                             onChanged: (val) {
                               if (val != null) {
                                 setState(() {
                                    // We need to store this. I will add the variable to the class in a later edit.
                                    // For now, let's assume the variable _selectedEventType exists.
                                    _selectedEventType = val;
                                 });
                               }
                             },
                           ),
                         ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_selectedEventType == 'global')
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true, // Ensure dropdown takes full width and handles overflow
                            initialValue: _selectedTimeZoneLabel, // Use value instead of initialValue for reactive updates
                            decoration: const InputDecoration(
                                labelText: 'Origin Time Zone / Country'),
                            items: _timeZones
                                .map((tz) => DropdownMenuItem<String>(
                                      value: tz['label'],
                                      child: Text(
                                        tz['label'],
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ))
                                .toList(),
                            selectedItemBuilder: (BuildContext context) {
                              return _timeZones.map<Widget>((tz) {
                                return Text(
                                  tz['label'],
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                );
                              }).toList();
                            },
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedTimeZoneLabel =
                                      _normalizeTimeZoneLabel(val);
                                  _selectedTimeZoneOffset = _offsetForZone(
                                    _selectedTimeZoneLabel,
                                    _selectedDate,
                                  );
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: InkWell(
                            onTap: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime(2024),
                                lastDate: DateTime(2030),
                              );
                              if (d != null) {
                                setState(() {
                                  _selectedDate = d;
                                  _selectedTimeZoneOffset = _offsetForZone(
                                    _selectedTimeZoneLabel,
                                    _selectedDate,
                                  );
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                  labelText: 'Origin Date'),
                              child: Text(
                                  '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                                  overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_selectedEventType == 'global') ...[
                      const SizedBox(height: 8),
                      Builder(
                        builder: (context) {
                          final originDateTime = DateTime.utc(
                            _selectedDate.year,
                            _selectedDate.month,
                            _selectedDate.day,
                            _selectedTime.hour,
                            _selectedTime.minute,
                          );
                          final utcDateTime = originDateTime.subtract(
                            Duration(hours: _selectedTimeZoneOffset),
                          );
                          final londonLocal = utcDateTime.add(
                            Duration(
                              hours: _offsetForZone(
                                'London (Auto DST)',
                                _selectedDate,
                              ),
                            ),
                          );
                          final parisLocal = utcDateTime.add(
                            Duration(
                              hours: _offsetForZone(
                                'Paris (Auto DST)',
                                _selectedDate,
                              ),
                            ),
                          );

                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade100),
                            ),
                            child: Text(
                              'UTC stored: ${_formatDateTime(utcDateTime)}  |  UK view: ${_formatDateTime(londonLocal)}  |  Paris view: ${_formatDateTime(parisLocal)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final t = await showTimePicker(
                                  context: context, initialTime: _selectedTime);
                              if (t != null) setState(() => _selectedTime = t);
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                  labelText: 'Origin Time'),
                              child: Text(_selectedTime.format(context)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _durationController,
                            decoration: const InputDecoration(
                              labelText: 'Duration (seconds)',
                              hintText: 'e.g. 60',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Automation Section
                    Text('Recurrence',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    
                    DropdownButtonFormField<String>(
                      initialValue: _recurrenceType,
                      decoration: const InputDecoration(
                        labelText: 'Repeat Event',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'None', child: Text('No Repeat (One-time)')),
                        DropdownMenuItem(value: 'Weekly', child: Text('Weekly (Same Day/Time)')),
                        DropdownMenuItem(value: 'Annually', child: Text('Annually (Same Date/Time)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _recurrenceType = val;
                            _isAutomated = val != 'None';
                          });
                          _saveCurrentSlotInMemory();
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (context) {
                        // Calculate accurate UTC time
                        final date = _selectedDate;
                        final localDateTime = DateTime.utc(date.year, date.month, date.day,
                            _selectedTime.hour, _selectedTime.minute);
                        final utcDateTime =
                            localDateTime.subtract(Duration(hours: _selectedTimeZoneOffset));
                        
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'This event will play simultaneously worldwide at UTC ${utcDateTime.hour.toString().padLeft(2, '0')}:${utcDateTime.minute.toString().padLeft(2, '0')}.',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Selected Date: ${date.day}/${date.month}/${date.year}',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            ),
                          ],
                        );
                      }
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // --- Content Section ---
          Listener(
            onPointerDown: (_) => setState(() {
              _showLearnMorePreview = false;
              _showNoticeBoardPreview = false;
            }),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Event Content',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                          labelText: 'Event Title',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _intentController,
                      decoration: InputDecoration(
                          labelText: 'Intent (e.g. Peace, Joy)',
                            helperText: 'Sets the shared intent for this event.',
                          border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),

                    // Visual
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _visualUrlController,
                            decoration: const InputDecoration(
                                labelText: 'Visual URL',
                                border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.add_photo_alternate,
                              color: Colors.indigo),
                          tooltip: 'Select Image Source',
                          onSelected: (value) {
                            if (value == 'library') {
                              _pickFromMediaLibrary(
                                typeFilter: 'visual', // Allow image or video
                                onSelect: (url) {
                                  setState(() {
                                    _visualUrlController.text = url;
                                    // Clear local preview since we are using a URL now
                                    _localVisualBytes = null;
                                    _localVisualName = null;
                                    _localVideoUrl = null;
                                    _localVideoViewId = null;
                                  });
                                },
                              );
                            } else if (value == 'clear') {
                              setState(() {
                                _visualUrlController.clear();
                                _localVisualBytes = null;
                                _localVisualName = null;
                                _localVideoUrl = null;
                                _localVideoViewId = null;
                              });
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'library',
                              child: Row(
                                children: [
                                  Icon(Icons.photo_library, color: Colors.grey),
                                  SizedBox(width: 8),
                                  Text('Select from Library'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'clear',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Clear / Remove',
                                      style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Sound
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _soundUrlController,
                            decoration: const InputDecoration(
                                labelText: 'Sound URL',
                                border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.audio_file,
                              color: Colors.indigo),
                          tooltip: 'Select Audio Source',
                          onSelected: (value) {
                            if (value == 'library') {
                              _pickFromMediaLibrary(
                                typeFilter: 'audio',
                                onSelect: (url) {
                                  setState(
                                      () => _soundUrlController.text = url);
                                },
                              );
                            } else if (value == 'clear') {
                              setState(() {
                                _soundUrlController.clear();
                              });
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'library',
                              child: Row(
                                children: [
                                  Icon(Icons.library_music, color: Colors.grey),
                                  SizedBox(width: 8),
                                  Text('Select from Library'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'clear',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Clear / Remove',
                                      style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // --- Learn More Section ---
          Listener(
            onPointerDown: (_) => setState(() => _showLearnMorePreview = true),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Learn More Section',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),

                    // Learn More Visual (Top 3/4)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _learnMoreContentController,
                            focusNode: _learnMoreContentFocus,
                            decoration: const InputDecoration(
                                labelText: 'Main Visual (Top 3/4)',
                                border: OutlineInputBorder()),
                            onChanged: (val) {
                              // Clear local preview if user types a URL
                              if (_localLearnMoreBytes != null) {
                                setState(() {
                                  _localLearnMoreBytes = null;
                                  _localLearnMoreName = null;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.add_photo_alternate,
                              color: Colors.indigo),
                          tooltip: 'Select Image Source',
                          onSelected: (value) {
                            if (value == 'library') {
                              _pickFromMediaLibrary(
                                typeFilter: 'any',
                                onSelect: (url) {
                                  setState(() {
                                    _learnMoreContentController.text = url;
                                    _localLearnMoreBytes =
                                        null; // Clear local preview
                                    _localLearnMoreName = null;
                                  });
                                },
                              );
                            } else if (value == 'clear') {
                              setState(() {
                                _learnMoreContentController.clear();
                                _localLearnMoreBytes = null;
                                _localLearnMoreName = null;
                                _localLearnMoreVideoViewId = null;
                              });
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'library',
                              child: Row(
                                children: [
                                  Icon(Icons.photo_library, color: Colors.grey),
                                  SizedBox(width: 8),
                                  Text('Select from Library'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'clear',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Clear / Remove',
                                      style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Learn More Bottom (1/4)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _learnMoreUrlController,
                            focusNode: _learnMoreUrlFocus,
                            decoration: const InputDecoration(
                                labelText:
                                    'Secondary Content / YouTube (Bottom 1/4)',
                                border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.video_library,
                              color: Colors.indigo),
                          tooltip: 'Select Content Source',
                          onSelected: (value) {
                            if (value == 'library') {
                              _pickFromMediaLibrary(
                                typeFilter: 'any', // Allow any type
                                onSelect: (url) {
                                  setState(
                                      () => _learnMoreUrlController.text = url);
                                },
                              );
                            } else if (value == 'youtube_link') {
                              showDialog(
                                context: context,
                                builder: (context) {
                                  final TextEditingController ytController =
                                      TextEditingController();
                                  return AlertDialog(
                                    title: const Text('Add YouTube Link'),
                                    content: TextField(
                                      controller: ytController,
                                      decoration: const InputDecoration(
                                        labelText: 'YouTube URL',
                                        hintText:
                                            'https://www.youtube.com/watch?v=...',
                                      ),
                                      autofocus: true,
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          if (ytController.text.isNotEmpty) {
                                            setState(() =>
                                                _learnMoreUrlController.text =
                                                    ytController.text);
                                          }
                                          Navigator.pop(context);
                                        },
                                        child: const Text('Add'),
                                      ),
                                    ],
                                  );
                                },
                              );
                            } else if (value == 'find_youtube') {
                              launchUrl(Uri.parse('https://www.youtube.com'),
                                  mode: LaunchMode.externalApplication);
                            } else if (value == 'clear') {
                              setState(() {
                                _learnMoreUrlController.clear();
                              });
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'library',
                              child: Row(
                                children: [
                                  Icon(Icons.perm_media, color: Colors.grey),
                                  SizedBox(width: 8),
                                  Text('Select from Library'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'youtube_link',
                              child: Row(
                                children: [
                                  Icon(Icons.link, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Add YouTube Link'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'find_youtube',
                              child: Row(
                                children: [
                                  Icon(Icons.search, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Find on YouTube'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'clear',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Clear / Remove',
                                      style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // --- Notice Board Section ---
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Notice Board Section',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _noticeBoardTextController,
                    decoration: const InputDecoration(
                      labelText: 'Notice Board Message',
                      hintText:
                          'Enter the message to display on the Notice Board',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _noticeBoardBgController,
                          decoration: const InputDecoration(
                            labelText: 'Background Image URL',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.add_photo_alternate,
                            color: Colors.indigo),
                        tooltip: 'Select Image Source',
                        onSelected: (value) {
                          if (value == 'library') {
                            _pickFromMediaLibrary(
                              typeFilter: 'image',
                              onSelect: (url) {
                                setState(
                                    () => _noticeBoardBgController.text = url);
                              },
                            );
                          } else if (value == 'clear') {
                            setState(() {
                              _noticeBoardBgController.clear();
                            });
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'library',
                            child: Row(
                              children: [
                                Icon(Icons.photo_library, color: Colors.grey),
                                SizedBox(width: 8),
                                Text('Select from Library'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'clear',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Clear / Remove',
                                    style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text('Visibility Settings', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 16),
                  
                  // Show Before Slider
                  Row(
                    children: [
                      const Icon(Icons.visibility, size: 20, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Show on Notice Board: ${_noticeBoardShowBeforeMinutes >= 10080 ? "${(_noticeBoardShowBeforeMinutes / 10080).toStringAsFixed(1)} weeks" : _noticeBoardShowBeforeMinutes >= 1440 ? "${(_noticeBoardShowBeforeMinutes / 1440).toStringAsFixed(1)} days" : "${(_noticeBoardShowBeforeMinutes / 60).toStringAsFixed(1)} hours"} before event'),
                            Slider(
                              value: _noticeBoardShowBeforeMinutes.toDouble().clamp(0, 40320), // Max 28 days (4 weeks)
                              min: 0,
                              max: 40320,
                              divisions: 672, // Hourly steps approx (40320 / 60)
                              label: '${(_noticeBoardShowBeforeMinutes / 60).toStringAsFixed(0)} hours',
                              onChanged: (val) => setState(() => _noticeBoardShowBeforeMinutes = val.toInt()),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Hide After Slider
                  Row(
                    children: [
                      const Icon(Icons.timer_off, size: 20, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Keep visible after event: ${_noticeBoardVisibilityAfterMinutes == 0 ? "Remove Immediately" : "${(_noticeBoardVisibilityAfterMinutes / 60).toStringAsFixed(1)} hours"}'),
                            Slider(
                              value: _noticeBoardVisibilityAfterMinutes.toDouble().clamp(0, 2880), // Max 48 hours
                              min: 0,
                              max: 2880,
                              divisions: 48,
                              label: '${(_noticeBoardVisibilityAfterMinutes / 60).toStringAsFixed(0)} hours',
                              onChanged: (val) => setState(() => _noticeBoardVisibilityAfterMinutes = val.toInt()),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.visibility),
                      label: const Text('View Notice Board Preview'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                      onPressed: () {
                        setState(() {
                          _showLearnMorePreview = false;
                          _showNoticeBoardPreview = true;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
