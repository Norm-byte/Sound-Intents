import 'package:flutter/material.dart';
import '../../models/event.dart';

class ContentEditorTab extends StatefulWidget {
  final List<Event> events;
  final Function(Event) onSave;

  const ContentEditorTab({
    super.key,
    required this.events,
    required this.onSave,
  });

  @override
  State<ContentEditorTab> createState() => _ContentEditorTabState();
}

class _ContentEditorTabState extends State<ContentEditorTab> {
  Event? _selectedEvent;
  final _contentController = TextEditingController();
  final _youtubeController = TextEditingController();
  bool _showPreview = false;
  String _editorMode = 'Markdown';

  void _loadEvent(Event e) {
    setState(() {
      _selectedEvent = e;
      _contentController.text = e.learnMoreContent ?? '';
      _youtubeController.text = e.learnMoreYoutubeUrl ?? '';
      _showPreview = false;
    });
  }

  void _saveContent() {
    if (_selectedEvent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an event first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final updated = _selectedEvent!.copyWith(
      learnMoreContent: _contentController.text.isEmpty ? null : _contentController.text,
      learnMoreYoutubeUrl: _youtubeController.text.isEmpty ? null : _youtubeController.text,
    );

    widget.onSave(updated);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Content saved successfully!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _clearEditor() {
    setState(() {
      _selectedEvent = null;
      _contentController.clear();
      _youtubeController.clear();
      _showPreview = false;
    });
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
                child: const Row(
                  children: [
                    Icon(Icons.event, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text(
                      'Select Event',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
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
                            'No events available.\n\nCreate events in the Event Creator tab first.',
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
                          final hasContent = (e.learnMoreContent?.isNotEmpty ?? false) ||
                              (e.learnMoreYoutubeUrl?.isNotEmpty ?? false);

                          return Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.indigo.shade100
                                  : Colors.transparent,
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.grey.shade200,
                                ),
                              ),
                            ),
                            child: ListTile(
                              selected: isSelected,
                              leading: Stack(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: e.isPublished
                                        ? Colors.green.shade100
                                        : Colors.orange.shade100,
                                    child: Icon(
                                      e.isPublished ? Icons.check_circle : Icons.drafts,
                                      size: 20,
                                      color: e.isPublished ? Colors.green : Colors.orange,
                                    ),
                                  ),
                                  if (hasContent)
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: Colors.blue,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
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
                                hasContent
                                    ? 'Has Learn More content'
                                    : 'No content yet',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: hasContent ? Colors.blue : Colors.grey,
                                ),
                              ),
                              onTap: () => _loadEvent(e),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        
        // Vertical Divider
        VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
        
        // Main Editor Area
        Expanded(
          child: _selectedEvent == null
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.article, size: 80, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Select an event to edit its Learn More content',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Header Bar
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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Content Editor',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Editing: ${_selectedEvent!.title}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'Markdown',
                                label: Text('Markdown'),
                                icon: Icon(Icons.code, size: 16),
                              ),
                              ButtonSegment(
                                value: 'Rich Text',
                                label: Text('Rich Text'),
                                icon: Icon(Icons.text_fields, size: 16),
                              ),
                            ],
                            selected: {_editorMode},
                            onSelectionChanged: (Set<String> selection) {
                              setState(() {
                                _editorMode = selection.first;
                              });
                            },
                          ),
                          const SizedBox(width: 16),
                          Switch(
                            value: _showPreview,
                            onChanged: (v) => setState(() => _showPreview = v),
                          ),
                          const Text('Preview'),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            onPressed: _saveContent,
                            icon: const Icon(Icons.save),
                            label: const Text('Save'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _clearEditor,
                            icon: const Icon(Icons.close),
                            tooltip: 'Clear selection',
                          ),
                        ],
                      ),
                    ),
                    
                    // Content Area
                    Expanded(
                      child: _showPreview
                          ? Row(
                              children: [
                                Expanded(child: _buildEditor()),
                                VerticalDivider(
                                  width: 1,
                                  thickness: 1,
                                  color: Colors.grey.shade300,
                                ),
                                Expanded(child: _buildPreview()),
                              ],
                            )
                          : _buildEditor(),
                    ),
                  ],
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
          // Toolbar (placeholder for rich text mode)
          if (_editorMode == 'Rich Text')
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.format_bold),
                      onPressed: () {},
                      tooltip: 'Bold (Coming Soon)',
                    ),
                    IconButton(
                      icon: const Icon(Icons.format_italic),
                      onPressed: () {},
                      tooltip: 'Italic (Coming Soon)',
                    ),
                    IconButton(
                      icon: const Icon(Icons.format_underlined),
                      onPressed: () {},
                      tooltip: 'Underline (Coming Soon)',
                    ),
                    const VerticalDivider(),
                    IconButton(
                      icon: const Icon(Icons.format_list_bulleted),
                      onPressed: () {},
                      tooltip: 'Bullet List (Coming Soon)',
                    ),
                    IconButton(
                      icon: const Icon(Icons.format_list_numbered),
                      onPressed: () {},
                      tooltip: 'Numbered List (Coming Soon)',
                    ),
                    const VerticalDivider(),
                    IconButton(
                      icon: const Icon(Icons.link),
                      onPressed: () {},
                      tooltip: 'Insert Link (Coming Soon)',
                    ),
                    IconButton(
                      icon: const Icon(Icons.image),
                      onPressed: () {},
                      tooltip: 'Insert Image (Coming Soon)',
                    ),
                  ],
                ),
              ),
            ),
          
          if (_editorMode == 'Rich Text') const SizedBox(height: 16),
          
          // Content Text Area
          const Text(
            'Learn More Content',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _contentController,
            maxLines: 16,
            decoration: InputDecoration(
              hintText: _editorMode == 'Markdown'
                  ? 'Enter markdown content here...\n\n# Heading\n## Subheading\n- Bullet point\n**Bold text**\n*Italic text*'
                  : 'Enter your content here...',
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
          
          const SizedBox(height: 24),
          
          // YouTube URL Field
          const Text(
            'YouTube Video',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _youtubeController,
            decoration: InputDecoration(
              labelText: 'YouTube Embed URL',
              hintText: 'https://www.youtube.com/embed/VIDEO_ID',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.video_library),
              suffixIcon: _youtubeController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _youtubeController.clear();
                        setState(() {});
                      },
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          
          if (_youtubeController.text.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Video will be embedded in the Learn More modal',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          const SizedBox(height: 24),
          
          // File Upload Section (Placeholder)
          const Text(
            'Attachments',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Icon(Icons.upload_file, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  'File upload coming soon',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Upload PDFs, documents, or images to attach to Learn More content',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      color: Colors.grey.shade50,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.preview, color: Colors.indigo.shade700),
                const SizedBox(width: 8),
                Text(
                  'Live Preview',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            
            // Content Preview
            if (_contentController.text.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Content:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _contentController.text,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // YouTube Preview
            if (_youtubeController.text.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'YouTube Video:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.play_circle_outline, size: 64, color: Colors.white.withValues(alpha: 0.8)),
                            const SizedBox(height: 8),
                            Text(
                              'YouTube Player',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                            ),
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                _youtubeController.text,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.6),
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // Empty State
            if (_contentController.text.isEmpty && _youtubeController.text.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Preview will appear here as you type',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _contentController.dispose();
    _youtubeController.dispose();
    super.dispose();
  }
}
