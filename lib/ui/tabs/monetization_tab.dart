import 'package:flutter/material.dart';
import '../../models/monetization_offer.dart';
import '../../repositories/monetization_repository.dart';
import '../widgets/phone_preview_wrapper.dart';

class MonetizationTab extends StatefulWidget {
  const MonetizationTab({super.key});

  @override
  State<MonetizationTab> createState() => _MonetizationTabState();
}

class _MonetizationTabState extends State<MonetizationTab> {
  final MonetizationRepository _repo = MonetizationRepository();

  MonetizationOffer? _selectedOffer;
  
  // Form Controllers
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _rcIdController = TextEditingController();
  final _sendsController = TextEditingController();
  final _forumsController = TextEditingController();
  final _storageController = TextEditingController();
  
  // Presentation Controllers
  final _headlineController = TextEditingController();
  final _subheadController = TextEditingController();
  final _ctaController = TextEditingController();
  Color _primaryColor = Colors.deepPurple;

  // Unlimited Toggles
  bool _unlimitedSends = false;
  bool _unlimitedForums = false;
  bool _unlimitedStorage = false;

  bool _hasAutoSelected = false;

  @override
  void initState() {
    super.initState();
    // Automatically fetch the latest live configuration to ensure the admin sees the real state immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repo.syncFromLive();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _rcIdController.dispose();
    _sendsController.dispose();
    _forumsController.dispose();
    _storageController.dispose();
    _headlineController.dispose();
    _subheadController.dispose();
    _ctaController.dispose();
    super.dispose();
  }

  void _selectOffer(MonetizationOffer? offer) {
    if (offer != null) {
      _titleController.text = offer.title;
      _descController.text = offer.description;
      _rcIdController.text = offer.revenueCatOfferingId;
      
      // Handle Limits & Unlimited Logic (Check for -1)
      final sends = offer.limits.maxMonthlySends;
      final forums = offer.limits.maxActiveForums;
      final storage = offer.limits.maxMediaStorageMb;

      _unlimitedSends = sends == -1;
      _unlimitedForums = forums == -1;
      _unlimitedStorage = storage == -1;

      _sendsController.text = _unlimitedSends ? '' : sends.toString();
      _forumsController.text = _unlimitedForums ? '' : forums.toString();
      _storageController.text = _unlimitedStorage ? '' : storage.toString();
      
      _headlineController.text = offer.presentation?.headline ?? '';
      _subheadController.text = offer.presentation?.subheadline ?? '';
      _ctaController.text = offer.presentation?.ctaText ?? 'Subscribe';
    } else {
      _clearForm();
    }
    
    // Set State AFTER setting values so UI updates
    setState(() {
      _selectedOffer = offer;
    });
  }

  void _clearForm() {
    _titleController.clear();
    _descController.clear();
    _rcIdController.clear();
    
    _unlimitedSends = false;
    _unlimitedForums = false;
    _unlimitedStorage = false;

    _sendsController.text = '50';
    _forumsController.text = '1';
    _storageController.text = '100';
    _headlineController.clear();
    _subheadController.clear();
    _ctaController.text = 'Subscribe';
  }

  Future<void> _saveCurrentOffer() async {
    // If creating new, we need an ID. Since we don't have a reliable generator here without extra deps,
    // we'll let the Repo handle ID generation if it's empty, or just use a timestamp if needed?
    // The previous code had `_repo.createOffer` which likely handles ID if empty.
    
    String id = _selectedOffer?.id ?? '';
    
    final limits = AppUsageLimits(
      maxMonthlySends: _unlimitedSends ? -1 : (int.tryParse(_sendsController.text) ?? 50),
      maxActiveForums: _unlimitedForums ? -1 : (int.tryParse(_forumsController.text) ?? 1),
      maxMediaStorageMb: _unlimitedStorage ? -1 : (int.tryParse(_storageController.text) ?? 100),
    );

    final presentation = PaywallPresentation(
      headline: _headlineController.text,
      subheadline: _subheadController.text,
      primaryColorHex: '#${_primaryColor.value.toRadixString(16).padLeft(8, '0').substring(2)}',
      ctaText: _ctaController.text,
    );

    final offer = MonetizationOffer(
      id: id, 
      title: _titleController.text,
      description: _descController.text,
      isActive: _selectedOffer?.isActive ?? false,
      revenueCatOfferingId: _rcIdController.text,
      limits: limits,
      presentation: presentation,
    );

    await _repo.saveDraftOffer(offer);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft Deal Saved!')),
      );
      _selectOffer(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LEFT: List of Deals
        Expanded(
          flex: 4,
          child: Card(
            child: _buildOfferList(),
          ),
        ),
        // RIGHT: Editor (No Preview)
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

  Widget _buildOfferList() {
    return Column(
      children: [
        // Action Buttons
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
               ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53935), foregroundColor: Colors.white),
                onPressed: () async {
                   final confirm = await showDialog<bool>(
                      context: context, 
                      builder: (c) => AlertDialog(
                        title: const Text('Publish All Changes?'),
                        content: const Text('This will overwrite the LIVE User App configuration with your current drafts.'),
                        actions: [
                          TextButton(onPressed: ()=>Navigator.pop(c, false), child: const Text('Cancel')),
                          TextButton(onPressed: ()=>Navigator.pop(c, true), child: const Text('Publish')),
                        ],
                      )
                   );
                   if (confirm == true) {
                     await _repo.publishToLive();
                     if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Published to Live!')));
                   }
                },
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Publish to Live App'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                 onPressed: () async {
                   final confirm = await showDialog<bool>(
                      context: context, 
                      builder: (c) => AlertDialog(
                        title: const Text('Discard Drafts?'),
                        content: const Text('This will loose all unsaved changes and reload from the Live App.'),
                        actions: [
                          TextButton(onPressed: ()=>Navigator.pop(c, false), child: const Text('Cancel')),
                          TextButton(onPressed: ()=>Navigator.pop(c, true), child: const Text('Discard & Sync')),
                        ],
                      )
                   );
                   if (confirm == true) {
                     await _repo.syncFromLive();
                     if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Synced from Live!')));
                   }
                },
                icon: const Icon(Icons.sync),
                label: const Text('Discard & Sync from Live'),
              ),
               const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _selectOffer(MonetizationOffer(
                  id: '',
                  title: 'New Deal',
                  description: '',
                  isActive: false,
                  revenueCatOfferingId: '',
                  limits: AppUsageLimits(),
                )), 
                icon: const Icon(Icons.add),
                label: const Text('Create Draft Deal'),
              ),
            ],
          ),
        ),
        
        Expanded(
          child: StreamBuilder<List<MonetizationOffer>>(
            stream: _repo.getDraftOffersStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              
              final offers = snapshot.data!;

              // Auto-select the Active deal (or first) on initial load
              if (!_hasAutoSelected && offers.isNotEmpty) {
                _hasAutoSelected = true;
                
                // Try to find active, otherwise take the first one
                final defaultOffer = offers.cast<MonetizationOffer?>().firstWhere(
                  (o) => o?.isActive == true,
                  orElse: () => offers.first,
                );
                
                if (defaultOffer != null) {
                   WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _selectOffer(defaultOffer);
                   });
                }
              }

              return ListView.builder(
                itemCount: offers.length,
                itemBuilder: (context, index) {
                  final offer = offers[index];
                  final isLive = offer.isActive;
                  
                  return Container(
                    decoration: isLive ? BoxDecoration(color: Colors.green.withOpacity(0.1), border: Border(left: BorderSide(color: Colors.green, width: 4))) : null,
                    child: ListTile(
                      title: Text(offer.title, style: TextStyle(fontWeight: isLive ? FontWeight.bold : FontWeight.normal)),
                      subtitle: Text(isLive ? 'Currently Linked to User App' : '${offer.limits.maxMonthlySends} sends per day'),
                      trailing: Switch(
                        value: offer.isActive,
                        activeColor: Colors.green,
                        onChanged: (val) {
                           // Ensure only one can be active if we turn this one on
                           final updatedDiff = MonetizationOffer(
                              id: offer.id,
                              title: offer.title,
                              description: offer.description,
                              isActive: val,
                              revenueCatOfferingId: offer.revenueCatOfferingId,
                              limits: offer.limits,
                              presentation: offer.presentation,
                           );
                           _repo.saveDraftOffer(updatedDiff);
                        },
                      ),
                      selected: _selectedOffer?.id == offer.id,
                      onTap: () => _selectOffer(offer),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEditor() {
    if (_selectedOffer == null) return const Center(child: Text('Select a Deal from the list to Edit, or click "Create Draft Deal".'));
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ACTIVE INDICATOR BANNER
        if (_selectedOffer != null && _selectedOffer!.isActive)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withOpacity(0.2), 
              borderRadius: BorderRadius.circular(8), 
              border: Border.all(color: Colors.green)
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("ACTIVE LIVE DEAL", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)),
                      Text("Users see this configuration. RevenueCat ID: ${_rcIdController.text}", style: const TextStyle(color: Colors.black87)),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // HELP TEXT
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("How to Link to RevenueCat Paywalls:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
              SizedBox(height: 4),
              Text("1. In RevenueCat Dashboard: Create an Offering (e.g., 'premium_monthly').", style: TextStyle(fontSize: 12)),
              Text("2. In RevenueCat: Setup your Paywall UI there.", style: TextStyle(fontSize: 12)),
              Text("3. HERE: Paste that 'Offering ID' below.", style: TextStyle(fontSize: 12)),
              Text("4. HERE: Define the actual app limits (Sends, Rooms) that this plan unlocks.", style: TextStyle(fontSize: 12)),
              Text("5. Click 'Publish to Live App' on the left to activate.", style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Text('Core Configuration', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Internal Title', hintText: 'e.g. Premium Plan')),
        const SizedBox(height: 8),
        TextField(controller: _rcIdController, decoration: const InputDecoration(labelText: 'RevenueCat Offering ID', hintText: 'MUST match ID in RevenueCat exactly')),
        
        const Divider(height: 32),
        Text('Entitlements', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        
        // SENDS
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _sendsController, 
                enabled: !_unlimitedSends,
                decoration: const InputDecoration(labelText: 'Max Sends (Daily Limit)'),
                keyboardType: TextInputType.number,
                 onChanged: (v) => setState((){}), // rebuild preview
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => setState(() {
                _unlimitedSends = !_unlimitedSends;
                if (_unlimitedSends) _sendsController.clear();
              }),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _unlimitedSends ? Colors.blue.shade100 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _unlimitedSends ? Colors.blue : Colors.grey.shade300),
                ),
                child: const Text('∞', style: TextStyle(fontSize: 24, height: 1.0)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // FORUMS (CHAT ROOMS)
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _forumsController, 
                enabled: !_unlimitedForums,
                decoration: const InputDecoration(labelText: 'Max Chat Rooms'),
                keyboardType: TextInputType.number,
                 onChanged: (v) => setState((){}), // rebuild preview
              ),
            ),
             const SizedBox(width: 8),
            InkWell(
              onTap: () => setState(() {
                _unlimitedForums = !_unlimitedForums;
                 if (_unlimitedForums) _forumsController.clear();
              }),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _unlimitedForums ? Colors.blue.shade100 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _unlimitedForums ? Colors.blue : Colors.grey.shade300),
                ),
                child: const Text('∞', style: TextStyle(fontSize: 24, height: 1.0)),
              ),
            ),
          ],
        ),
        
        // STORAGE (Removed as per user request - 2026-01-23)
        // Users do not upload media, so this limit is irrelevant.
        /*
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _storageController, 
                enabled: !_unlimitedStorage,
                decoration: const InputDecoration(labelText: 'Max Media Storage (MB)'),
                keyboardType: TextInputType.number,
                 onChanged: (v) => setState((){}), 
              ),
            ),
             const SizedBox(width: 8),
            InkWell(
              onTap: () => setState(() {
                _unlimitedStorage = !_unlimitedStorage;
                 if (_unlimitedStorage) _storageController.clear();
              }),
               child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _unlimitedStorage ? Colors.blue.shade100 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _unlimitedStorage ? Colors.blue : Colors.grey.shade300),
                ),
                child: const Text('∞', style: TextStyle(fontSize: 24, height: 1.0)),
              ),
            ),
          ],
        ),
        */
        
        const Divider(height: 32),
        /*
        Text('Presentation Overrides', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        TextField(
          controller: _headlineController, 
          decoration: const InputDecoration(labelText: 'Marketing Headline'),
          onChanged: (v) => setState((){}), // rebuild preview
        ),
        TextField(
          controller: _subheadController, 
          decoration: const InputDecoration(labelText: 'Subtext'),
          onChanged: (v) => setState((){}), // rebuild preview
        ),
        TextField(
          controller: _ctaController, 
          decoration: const InputDecoration(labelText: 'Button Text'),
          onChanged: (v) => setState((){}), // rebuild preview
        ),
        
        const SizedBox(height: 32),
        */
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _saveCurrentOffer,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            padding: const EdgeInsets.all(20),
          ),
          child: const Text('SAVE DEAL'),
        )
      ],
    );
  }

  Widget _buildMockPaywall() {
    // This represents what the user would see.
    // We use the controller values to make the preview dynamic based on the selected deal.
    final headline = _headlineController.text.isNotEmpty ? _headlineController.text : (_titleController.text.isNotEmpty ? _titleController.text : 'Unlock Full Harmony');
    final subhead = _subheadController.text.isNotEmpty ? _subheadController.text : (_descController.text.isNotEmpty ? _descController.text : 'Join the global community and experience simultaneous intent without limits.');
    final buttonText = _ctaController.text.isNotEmpty ? _ctaController.text : 'View Subscription Options';

    return Stack(
      children: [
        // Background (Gradient simulation)
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.indigo.shade900, Colors.purple.shade900],
              begin: Alignment.topLeft, 
              end: Alignment.bottomRight
            )
          ),
        ),

        // Live Indicator (Hidden in real app, useful for Admin verification)
        Positioned(
           top: 0, left: 0, right: 0,
           child: Container(
             color: Colors.black87,
             padding: const EdgeInsets.all(8),
             child: Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                 const Text('LIVE PREVIEW V2', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold, decoration: TextDecoration.none)),
                 Row(
                   children: [
                      Icon(Icons.send, color: Colors.white70, size: 10),
                      const SizedBox(width: 4),
                      Text('${_unlimitedSends ? "∞" : _sendsController.text}', style: const TextStyle(color: Colors.white, fontSize: 10, decoration: TextDecoration.none)),
                      const SizedBox(width: 8),
                      Icon(Icons.forum, color: Colors.white70, size: 10),
                      const SizedBox(width: 4),
                      Text('${_unlimitedForums ? "∞" : _forumsController.text}', style: const TextStyle(color: Colors.white, fontSize: 10, decoration: TextDecoration.none)),
                   ],
                 )
               ],
             ),
           )
        ),
        
        // Content
        SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Banner to indicate this is a proxy for RevenueCat
              if (_rcIdController.text.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    'RC Offering: ${_rcIdController.text}',
                    style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace', decoration: TextDecoration.none),
                  ),
                ),

              const SizedBox(height: 10),
              const Icon(Icons.diamond_outlined, size: 80, color: Colors.amber),
              const SizedBox(height: 24),
              
              // HEADLINE
              Text(
                headline,
                style: const TextStyle(
                  fontSize: 24, // Slightly smaller for preview
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  decoration: TextDecoration.none
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              
              // SUBHEAD
              Text(
                subhead,
                style: const TextStyle(fontSize: 14, color: Colors.white70, decoration: TextDecoration.none),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              
              // Benefits List
               _buildMockBenefitRow(Icons.public, 'Join Worldwide Events'),
               _buildMockBenefitRow(Icons.forum, 'Access Community Chat'),
               _buildMockBenefitRow(Icons.history, 'Track Your Intent History'),
               _buildMockBenefitRow(Icons.star, 'Support the Platform'),

              const SizedBox(height: 30),

              // Subscription Action
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Choose Your Plan',
                      style: TextStyle(color: Colors.white70, fontSize: 12, decoration: TextDecoration.none),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: Container(
                         alignment: Alignment.center,
                         padding: const EdgeInsets.symmetric(vertical: 12),
                         decoration: BoxDecoration(
                           color: Colors.amber, 
                           borderRadius: BorderRadius.circular(12)
                         ),
                         child: Text(
                           buttonText,
                           style: const TextStyle(
                             fontSize: 14, 
                             fontWeight: FontWeight.bold, 
                             color: Colors.black87,
                             decoration: TextDecoration.none
                           ),
                         ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              const Text(
                'Restore Purchases',
                style: TextStyle(color: Colors.white54, fontSize: 10, decoration: TextDecoration.none),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMockBenefitRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.amber, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, decoration: TextDecoration.none))),
        ],
      ),
    );
  }
}
/*    
  Widget _buildFeatureRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blue),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }
}
*/
