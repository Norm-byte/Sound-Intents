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

  // Defined Tiers
  static const String TIER_FREE = 'tier_free';
  static const String TIER_STANDARD = 'tier_standard';
  static const String TIER_PRO = 'tier_pro';

  MonetizationOffer? _selectedOffer;
  
  // Form Controllers
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _rcIdController = TextEditingController();
  final _dailySendsController = TextEditingController();
  final _forumsController = TextEditingController();
  
  // Unlimited Toggles
  bool _unlimitedSends = false;
  bool _unlimitedForums = false;

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
      id: _selectedOffer!.id, // Keep the fixed ID (tier_free, etc)
      title: _titleController.text,
      description: _descController.text,
      isActive: true, // Tiers are always "active" in the config list
      revenueCatOfferingId: _selectedOffer!.id == TIER_FREE ? '' : _rcIdController.text,
      limits: limits,
      presentation: presentation,
    );

    await _repo.saveDraftOffer(updatedOffer);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${_getTierName(updatedOffer.id)} Configuration!')),
      );
      // Refresh selection to show saved state
      // Force rebuild of parent to update list
      setState(() {
         _selectedOffer = updatedOffer;
      });
    }
  }

  String _getTierName(String id) {
    switch (id) {
      case TIER_FREE: return 'Free Tier (Default)';
      case TIER_STANDARD: return 'Standard Tier';
      case TIER_PRO: return 'Pro Tier';
      default: return 'Unknown Tier';
    }
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
               const Text("Tier Configuration", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
               const SizedBox(height: 4),
               const Text("Configure the 3 levels of access for your app users.", style: TextStyle(color: Colors.grey)),
               const SizedBox(height: 16),
               
               ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935), foregroundColor: Colors.white, padding: const EdgeInsets.all(16)),
                onPressed: () async {
                   final confirm = await showDialog<bool>(
                      context: context, 
                      builder: (c) => AlertDialog(
                        title: const Text('Publish Configuration to App?'),
                        content: const Text('This will make these settings LIVE for all users immediately.\n\nEnsure RevenueCat IDs match exactly.'),
                        actions: [
                          TextButton(onPressed: ()=>Navigator.pop(c, false), child: const Text('Cancel')),
                          TextButton(onPressed: ()=>Navigator.pop(c, true), child: const Text('PUBLISH LIVE')),
                        ],
                      )
                   );
                   if (confirm == true) {
                     await _repo.publishToLive();
                     if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configuration Published to Live App!')));
                   }
                },
                icon: const Icon(Icons.cloud_upload),
                label: const Text('PUBLISH TIERS TO LIVE APP'),
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
              
              // We simulate the 3 tiers existing even if the DB is empty
              final dbOffers = snapshot.data ?? [];
              
              Widget buildTierTile(String id, IconData icon, Color color, String defaultTitle, int defaultDaily, int defaultRooms) {
                // Find in DB or create default
                final offer = dbOffers.firstWhere(
                  (o) => o.id == id,
                  orElse: () => MonetizationOffer(
                    id: id,
                    title: defaultTitle,
                    description: '',
                    isActive: true,
                    revenueCatOfferingId: '',
                    limits: AppUsageLimits(maxDailySends: 0, maxActiveForums: 0),
                  )
                );

                final isSelected = _selectedOffer?.id == id;

                // Auto-select Free on first load
                if (id == TIER_FREE && !_hasAutoSelected && dbOffers.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                       _hasAutoSelected = true;
                       _selectOffer(offer);
                    }
                  });
                }

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withOpacity(0.2),
                    child: Icon(icon, color: color),
                  ),
                  title: Text(_getTierName(id), style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${offer.title}\nLimit: ${offer.limits.maxDailySends == -1 ? "Unlimited" : offer.limits.maxDailySends} daily'),
                  isThreeLine: true,
                  selected: isSelected,
                  selectedTileColor: color.withOpacity(0.05),
                  onTap: () => _selectOffer(offer),
                  trailing: const Icon(Icons.chevron_right),
                );
              }

              return ListView(
                children: [
                  buildTierTile(TIER_FREE, Icons.money_off, Colors.grey, 'Use Free Version', 10, 0),
                  const Divider(),
                  buildTierTile(TIER_STANDARD, Icons.star_border, Colors.blue, 'Standard Monthly', 10, 2),
                  const Divider(),
                  buildTierTile(TIER_PRO, Icons.diamond, Colors.amber, 'Pro Subscription', 100, 22),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEditor() {
    if (_selectedOffer == null) return const Center(child: Text('Select a Tier from the list to Configure.'));
    
    final isFree = _selectedOffer!.id == TIER_FREE;
    final isStandard = _selectedOffer!.id == TIER_STANDARD;
    final isPro = _selectedOffer!.id == TIER_PRO;

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
                   isFree ? 'Configuring Default Limits for non-paying users.' 
                   : 'Configuring Paid Tier. Requires RevenueCat ID.',
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
            labelText: 'Internal Description', 
            hintText: 'e.g. Starter Plan',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        
        if (!isFree)
          TextField(
            controller: _rcIdController, 
            decoration: const InputDecoration(
              labelText: 'RevenueCat Entitlement Identifier', 
              hintText: 'e.g. starter_access or unlimited_access',
              helperText: 'Must match the Entitlement ID in RevenueCat (e.g. starter_access, unlimited_access).',
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
            child: Text('SAVE ${_getTierName(_selectedOffer!.id).toUpperCase()} SETTINGS'),
          ),
        ),
        
        const SizedBox(height: 16),
        const Center(child: Text('Remember to click "PUBLISH TIERS" on the left after saving changes.', style: TextStyle(color: Colors.grey))),
      ],
    );
  }
}
