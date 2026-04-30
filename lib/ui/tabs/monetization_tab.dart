import 'package:flutter/material.dart';
import '../../models/monetization_offer.dart';
import '../../repositories/monetization_repository.dart';

class MonetizationTab extends StatefulWidget {
  const MonetizationTab({super.key});

  @override
  State<MonetizationTab> createState() => _MonetizationTabState();
}

class _MonetizationTabState extends State<MonetizationTab> {
  final MonetizationRepository _repo = MonetizationRepository();

  MonetizationOffer? _selectedOffer;
  String? _selectedDraftSetId;
  
  // Form Controllers
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _rcIdController = TextEditingController();
  final _dailySendsController = TextEditingController();
  final _forumsController = TextEditingController();
  
  // Unlimited Toggles
  bool _unlimitedSends = false;
  bool _unlimitedForums = false;
  final _draftSetNameController = TextEditingController();

  bool _hasAutoSelected = false;

  @override
  void initState() {
    super.initState();
    // Sync live config to drafts on load so admin sees current state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repo.syncFromLive();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _rcIdController.dispose();
    _dailySendsController.dispose();
    _forumsController.dispose();
    _draftSetNameController.dispose();
    super.dispose();
  }

  void _selectOffer(MonetizationOffer offer) {
    _titleController.text = offer.title;
    _descController.text = offer.description;
    _rcIdController.text = offer.revenueCatOfferingId;
    
    // Limits
    final dailySends = offer.limits.maxDailySends;
    final forums = offer.limits.maxActiveForums;

    _unlimitedSends = dailySends == -1;
    _unlimitedForums = forums == -1;

    _dailySendsController.text = _unlimitedSends ? '' : dailySends.toString();
    _forumsController.text = _unlimitedForums ? '' : forums.toString();
    
    setState(() {
      _selectedOffer = offer;
    });
  }

  Future<void> _saveSelectedTier() async {
    if (_selectedOffer == null) return;
    
    final limits = AppUsageLimits(
      maxDailySends: _unlimitedSends ? -1 : (int.tryParse(_dailySendsController.text) ?? 10),
      maxMonthlySends: _unlimitedSends ? -1 : ((int.tryParse(_dailySendsController.text) ?? 10) * 30), // Fallback calculation
      maxActiveForums: _unlimitedForums ? -1 : (int.tryParse(_forumsController.text) ?? 1),
    );

    // Preserve presentation logic if needed, or use default
    final presentation = _selectedOffer!.presentation;

    final updatedOffer = MonetizationOffer(
      id: _selectedOffer!.id,
      title: _titleController.text,
      description: _descController.text,
      isActive: true,
      revenueCatOfferingId: _rcIdController.text.trim(),
      limits: limits,
      presentation: presentation,
    );

    await _repo.saveDraftOffer(updatedOffer);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${updatedOffer.title} card!')),
      );
      setState(() {
         _selectedOffer = updatedOffer;
      });
    }
  }

  Future<void> _createDraftSet({required bool fromCurrentDraft}) async {
    final defaultName = fromCurrentDraft ? 'Snapshot ${DateTime.now().toIso8601String().substring(0, 19)}' : 'Blank Draft ${DateTime.now().toIso8601String().substring(0, 19)}';
    _draftSetNameController.text = defaultName;

    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(fromCurrentDraft ? 'Create Snapshot from Current Draft' : 'Create New Blank Draft'),
        content: TextField(
          controller: _draftSetNameController,
          decoration: const InputDecoration(
            labelText: 'Draft Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(c, _draftSetNameController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    final setId = await _repo.createDraftSet(name: name, fromCurrentDraft: fromCurrentDraft);
    if (!fromCurrentDraft) {
      await _repo.clearDraftOffers();
      _selectedOffer = null;
      _hasAutoSelected = false;
    }

    if (mounted) {
      setState(() {
        _selectedDraftSetId = setId;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(fromCurrentDraft ? 'Snapshot created.' : 'Blank draft created. Add cards on the left.')),
      );
    }
  }

  Future<void> _saveCurrentDraftToSelectedSet() async {
    if (_selectedDraftSetId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a draft set first.')),
      );
      return;
    }

    await _repo.saveCurrentDraftToSet(_selectedDraftSetId!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Current draft saved to selected set.')),
    );
  }

  Future<void> _loadSelectedSet() async {
    if (_selectedDraftSetId == null) return;

    await _repo.loadSetToCurrentDraft(_selectedDraftSetId!);
    if (!mounted) return;
    setState(() {
      _selectedOffer = null;
      _hasAutoSelected = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Loaded selected draft set into editor.')),
    );
  }

  Future<void> _deleteSelectedSet() async {
    if (_selectedDraftSetId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Selected Draft Set?'),
        content: const Text('This deletes the selected saved draft set. Current editor state is not automatically changed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;

    await _repo.deleteDraftSet(_selectedDraftSetId!);
    if (!mounted) return;
    setState(() {
      _selectedDraftSetId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Draft set deleted.')),
    );
  }

  String _slugify(String value) {
    final cleaned = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'offer' : cleaned;
  }

  Future<void> _addCard() async {
    final titleController = TextEditingController();
    final idController = TextEditingController();

    final shouldCreate = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add Deal Card'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Card Title',
                hintText: 'e.g. Harmony 100',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                if (idController.text.isEmpty || idController.text.startsWith('offer_')) {
                  idController.text = 'offer_${_slugify(value)}';
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: idController,
              decoration: const InputDecoration(
                labelText: 'Card ID',
                hintText: 'e.g. offer_harmony_100',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Create Card')),
        ],
      ),
    );

    if (shouldCreate != true) return;

    final title = titleController.text.trim();
    final id = idController.text.trim().isEmpty
        ? 'offer_${_slugify(title)}_${DateTime.now().millisecondsSinceEpoch}'
        : idController.text.trim();

    if (title.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Card title is required.')),
      );
      return;
    }

    final offer = MonetizationOffer(
      id: id,
      title: title,
      description: '',
      isActive: true,
      revenueCatOfferingId: '',
      limits: AppUsageLimits(maxDailySends: 10, maxActiveForums: 1),
    );

    await _repo.saveDraftOffer(offer);
    if (!mounted) return;
    _selectOffer(offer);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Card created. Configure it on the right panel.')),
    );
  }

  Future<void> _removeOffer(String offerId, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove Card?'),
        content: Text('Delete "$title" from this draft?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete Card')),
        ],
      ),
    );

    if (confirm != true) return;

    await _repo.deleteDraftOffer(offerId);
    if (!mounted) return;
    if (_selectedOffer?.id == offerId) {
      setState(() {
        _selectedOffer = null;
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Card removed from draft.')),
    );
  }

  Future<void> _publishDraftToLive(List<MonetizationOffer> draftOffers) async {
    final hasFreeTier = draftOffers.any((o) => o.id == 'tier_free');
    final warning = hasFreeTier
        ? 'This will make these settings LIVE for all users immediately.\n\nEnsure RevenueCat IDs match exactly.'
        : 'No tier_free card was found. Non-subscribed users will use hardcoded app fallback limits.\n\nPublish anyway?';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Publish Configuration to App?'),
        content: Text(warning),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('PUBLISH LIVE')),
        ],
      ),
    );

    if (confirm != true) return;
    await _repo.publishToLive();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuration published to live app!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LEFT: Tier List
        Expanded(
          flex: 4,
          child: Card(
            child: _buildTierList(),
          ),
        ),
        // RIGHT: Editor
        Expanded(
          flex: 6,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildEditor(),
          ),
        ),
      ],
    );
  }

  Widget _buildTierList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
               const Text("Deals / Offers Configuration", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
               const SizedBox(height: 4),
               const Text("Create draft sets, add/remove cards, then publish to live.", style: TextStyle(color: Colors.grey)),
               const SizedBox(height: 16),

               StreamBuilder<List<MonetizationDraftSet>>(
                stream: _repo.getDraftSetsStream(),
                builder: (context, snapshot) {
                  final sets = snapshot.data ?? [];

                  if (_selectedDraftSetId == null && sets.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() {
                        _selectedDraftSetId = sets.first.id;
                      });
                    });
                  }

                  final selectedExists = _selectedDraftSetId != null && sets.any((s) => s.id == _selectedDraftSetId);
                  final dropdownValue = selectedExists ? _selectedDraftSetId : null;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        value: dropdownValue,
                        items: sets
                            .map(
                              (s) => DropdownMenuItem<String>(
                                value: s.id,
                                child: Text(s.name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => _selectedDraftSetId = value),
                        decoration: const InputDecoration(
                          labelText: 'Saved Draft Sets',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _createDraftSet(fromCurrentDraft: false),
                            icon: const Icon(Icons.add),
                            label: const Text('New Blank Draft'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _createDraftSet(fromCurrentDraft: true),
                            icon: const Icon(Icons.copy_all),
                            label: const Text('Snapshot Current'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _selectedDraftSetId == null ? null : _saveCurrentDraftToSelectedSet,
                            icon: const Icon(Icons.save),
                            label: const Text('Save to Selected'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _selectedDraftSetId == null ? null : _loadSelectedSet,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Load Selected'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _selectedDraftSetId == null ? null : _deleteSelectedSet,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete Selected'),
                          ),
                        ],
                      ),
                    ],
                  );
                },
               ),

               const SizedBox(height: 16),
               
               ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935), foregroundColor: Colors.white, padding: const EdgeInsets.all(16)),
                onPressed: null,
                icon: const Icon(Icons.cloud_upload),
                label: const Text('SELECT A CARD LIST BELOW, THEN PUBLISH'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                 onPressed: () async {
                   final confirm = await showDialog<bool>(
                      context: context, 
                      builder: (c) => AlertDialog(
                        title: const Text('Discard Drafts?'),
                        content: const Text('Revert to what is currently live in the app?'),
                        actions: [
                          TextButton(onPressed: ()=>Navigator.pop(c, false), child: const Text('Cancel')),
                          TextButton(onPressed: ()=>Navigator.pop(c, true), child: const Text('Discard & Sync')),
                        ],
                      )
                   );
                   if (confirm == true) {
                     await _repo.syncFromLive();
                     // Trigger re-select if needed
                     if (mounted) setState(() {}); 
                     if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Synced from Live!')));
                   }
                },
                icon: const Icon(Icons.sync),
                label: const Text('Discard Changes & Sync from Live'),
              ),
            ],
          ),
        ),
        
        Expanded(
          child: StreamBuilder<List<MonetizationOffer>>(
            stream: _repo.getDraftOffersStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));

              final dbOffers = (snapshot.data ?? [])
                ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

              if (!_hasAutoSelected && dbOffers.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _hasAutoSelected = true;
                  _selectOffer(dbOffers.first);
                });
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _addCard,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Card'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: dbOffers.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'No cards in this draft. Click "Add Card" or load a saved draft set.',
                                style: TextStyle(color: Colors.grey.shade700),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: dbOffers.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final offer = dbOffers[index];
                              final isSelected = _selectedOffer?.id == offer.id;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue.withOpacity(0.12),
                                  child: const Icon(Icons.style, color: Colors.blue),
                                ),
                                title: Text(offer.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                  'ID: ${offer.id}\nRC: ${offer.revenueCatOfferingId.isEmpty ? "(none)" : offer.revenueCatOfferingId}',
                                ),
                                isThreeLine: true,
                                selected: isSelected,
                                selectedTileColor: Colors.blue.withOpacity(0.06),
                                onTap: () => _selectOffer(offer),
                                trailing: IconButton(
                                  tooltip: 'Delete Card',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _removeOffer(offer.id, offer.title),
                                ),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(14),
                        ),
                        onPressed: () => _publishDraftToLive(dbOffers),
                        icon: const Icon(Icons.cloud_upload),
                        label: const Text('PUBLISH CURRENT DRAFT TO LIVE APP'),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEditor() {
    if (_selectedOffer == null) {
      return const Center(child: Text('Select a card from the left to configure it.'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.blue.shade50,
          child: Row(
            children: [
               Icon(Icons.info_outline, color: Colors.blue.shade700),
               const SizedBox(width: 16),
               Expanded(
                 child: Text(
                   _selectedOffer!.id == 'tier_free'
                       ? 'Configuring default limits for non-paying users.'
                       : 'Configure limits and optionally map this card to a RevenueCat entitlement ID.',
                   style: TextStyle(color: Colors.blue.shade900),
                 )
               ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Text('Product Details', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        
        TextField(
          controller: _titleController, 
          decoration: const InputDecoration(
            labelText: 'Card Title', 
            hintText: 'e.g. Starter Plan',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _descController,
          decoration: const InputDecoration(
            labelText: 'Description',
            hintText: 'Optional internal note',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        
        TextField(
          controller: _rcIdController,
          decoration: const InputDecoration(
            labelText: 'RevenueCat Entitlement Identifier',
            hintText: 'e.g. starter_access, unlimited_access, or product ID',
            helperText: 'Supports entitlement IDs or product IDs. Use comma-separated IDs if needed. Leave blank for non-subscriber/default cards.',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.vpn_key),
          ),
        ),
        
        const Divider(height: 48),
        Text('Usage Limits', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        
        // SENDS
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _dailySendsController, 
                enabled: !_unlimitedSends,
                decoration: const InputDecoration(labelText: 'Max Messages (Daily Limit)', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                 onChanged: (v) => setState((){}), 
              ),
            ),
            const SizedBox(width: 16),
            InkWell(
              onTap: () => setState(() {
                _unlimitedSends = !_unlimitedSends;
                if (_unlimitedSends) _dailySendsController.clear();
              }),
              child: Container(
                height: 56, width: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _unlimitedSends ? Colors.blue.shade100 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _unlimitedSends ? Colors.blue : Colors.grey.shade400),
                ),
                child: const Text('∞', style: TextStyle(fontSize: 24, height: 1.0)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        // FORUMS (CHAT ROOMS)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _forumsController, 
                enabled: !_unlimitedForums,
                decoration: const InputDecoration(labelText: 'Max Chat Rooms', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                 onChanged: (v) => setState((){}), 
              ),
            ),
             const SizedBox(width: 16),
            InkWell(
              onTap: () => setState(() {
                _unlimitedForums = !_unlimitedForums;
                 if (_unlimitedForums) _forumsController.clear();
              }),
              child: Container(
                 height: 56, width: 60,
                 alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _unlimitedForums ? Colors.blue.shade100 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _unlimitedForums ? Colors.blue : Colors.grey.shade400),
                ),
                child: const Text('∞', style: TextStyle(fontSize: 24, height: 1.0)),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 48),
        
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _saveSelectedTier,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('SAVE CARD SETTINGS'),
          ),
        ),
        
        const SizedBox(height: 16),
        const Center(child: Text('Remember to click "Publish Current Draft" on the left after saving changes.', style: TextStyle(color: Colors.grey))),
      ],
    );
  }
}
