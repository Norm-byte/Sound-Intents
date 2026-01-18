import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  bool _isAuthenticated = false;
  String? _storedSecurityPassword;
  String? _storedVipCode;
  String? _storedDirectVipCode;
  bool _isLoadingAuth = true;

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

  @override
  void initState() {
    super.initState();
    _loadAuthSecrets();
  }

  Future<void> _loadAuthSecrets() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance.collection('admin_users').doc(user.uid).get();
        
        // Fetch VIP Code from vip_codes collection
        String? vipCollectionCode;
        try {
          final vipQuery = await FirebaseFirestore.instance
              .collection('vip_codes')
              .where('assignee', isEqualTo: user.email)
              .get();
              
          if (vipQuery.docs.isNotEmpty) {
             final superAdminCode = vipQuery.docs.firstWhere(
              (d) => d.data()['type'] == 'super_admin', 
              orElse: () => vipQuery.docs.first
            );
            vipCollectionCode = superAdminCode.data()['code'];
          }
        } catch (e) {
          debugPrint('Error fetching vip_codes: $e');
        }

        if (mounted) {
          setState(() {
            _storedSecurityPassword = userDoc.data()?['security_password'];
            _storedDirectVipCode = userDoc.data()?['vipCode'];
            _storedVipCode = vipCollectionCode;
            _isLoadingAuth = false;
          });
        }
      } else {
         if(mounted) setState(() => _isLoadingAuth = false);
      }
    } catch (e) {
      debugPrint('Error loading auth secrets: $e');
      if (mounted) setState(() => _isLoadingAuth = false);
    }
  }

  void _unlockSettings(String input) {
    if (input.isEmpty) return;
    
    bool unlocked = false;
    
    // 1. Check against Security Password
    if (_storedSecurityPassword != null && input == _storedSecurityPassword) {
      unlocked = true;
    }
    // 2. Check against VIP Code (from collection)
    else if (_storedVipCode != null && input == _storedVipCode) {
      unlocked = true;
    }
    // 3. Check against Direct VIP Code (from admin_users)
    else if (_storedDirectVipCode != null && input == _storedDirectVipCode) {
      unlocked = true;
    }
    // 4. Backup / Super Admin Override
    else if (input == '1234') { 
       // unlocked = true; 
    }

    if (unlocked) {
      setState(() {
        _isAuthenticated = true;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Incorrect password or VIP code'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _selectOffer(MonetizationOffer? offer) {
    setState(() {
      _selectedOffer = offer;
    });
    
    if (offer != null) {
      _titleController.text = offer.title;
      _descController.text = offer.description;
      _rcIdController.text = offer.revenueCatOfferingId;
      _sendsController.text = offer.limits.maxMonthlySends.toString();
      _forumsController.text = offer.limits.maxActiveForums.toString();
      _storageController.text = offer.limits.maxMediaStorageMb.toString();
      
      _headlineController.text = offer.presentation?.headline ?? '';
      _subheadController.text = offer.presentation?.subheadline ?? '';
      _ctaController.text = offer.presentation?.ctaText ?? 'Subscribe';
      // _primaryColor = ... parse hex
    } else {
      _clearForm();
    }
  }

  void _clearForm() {
    _titleController.clear();
    _descController.clear();
    _rcIdController.clear();
    _sendsController.text = '50';
    _forumsController.text = '1';
    _storageController.text = '100';
    _headlineController.clear();
    _subheadController.clear();
    _ctaController.text = 'Subscribe';
  }

  Future<void> _saveCurrentOffer() async {
    final offer = MonetizationOffer(
      id: _selectedOffer?.id ?? '', 
      title: _titleController.text,
      description: _descController.text,
      isActive: _selectedOffer?.isActive ?? false,
      revenueCatOfferingId: _rcIdController.text,
      limits: AppUsageLimits(
        maxMonthlySends: int.tryParse(_sendsController.text) ?? 50,
        maxActiveForums: int.tryParse(_forumsController.text) ?? 1,
        maxMediaStorageMb: int.tryParse(_storageController.text) ?? 100,
      ),
      presentation: PaywallPresentation(
        headline: _headlineController.text,
        subheadline: _subheadController.text,
        primaryColorHex: '#${_primaryColor.value.toRadixString(16).padLeft(8, '0').substring(2)}',
        ctaText: _ctaController.text,
      ),
    );

    await _repo.saveOffer(offer);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deal Saved!')),
      );
      _selectOffer(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return _buildauthScreen();
    }

    return Row(
      children: [
        // LEFT: List of Deals
        Expanded(
          flex: 1,
          child: _buildOfferList(),
        ),
        // MIDDLE: Editor
        Expanded(
          flex: 2,
          child: _buildEditor(),
        ),
        // RIGHT: Live Preview
        Expanded(
          flex: 2,
          child: _buildPreviewPane(),
        ),
      ],
    );
  }

  Widget _buildauthScreen() {
    if (_isLoadingAuth) {
      return const Center(child: CircularProgressIndicator());
    }

    final passCtrl = TextEditingController();
    return Center(
      child: Card(
        elevation: 4,
        margin: const EdgeInsets.all(32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
               Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_outline, size: 48, color: Colors.red.shade700),
              ),
              const SizedBox(height: 24),
              const Text(
                'Restricted Access', 
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)
              ),
              const SizedBox(height: 12),
              Text(
                'This area contains sensitive financial configuration.\nPlease enter your Security Password or VIP Code to access it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, height: 1.5),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password / VIP Code',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.vpn_key),
                ),
                onSubmitted: _unlockSettings,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _unlockSettings(passCtrl.text),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Unlock Manager'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfferList() {
    return StreamBuilder<List<MonetizationOffer>>(
      stream: _repo.getOffersStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton.icon(
                onPressed: () => _selectOffer(MonetizationOffer(
                  id: '',
                  title: 'New Deal',
                  description: '',
                  isActive: false,
                  revenueCatOfferingId: '',
                  limits: AppUsageLimits(),
                )), 
                icon: const Icon(Icons.add),
                label: const Text('Create New Deal'),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) {
                  final offer = snapshot.data![index];
                  return ListTile(
                    title: Text(offer.title),
                    subtitle: Text('${offer.limits.maxMonthlySends} sends'),
                    trailing: Switch(
                      value: offer.isActive,
                      onChanged: (val) => _repo.setActiveOffer(offer.id, val),
                    ),
                    selected: _selectedOffer?.id == offer.id,
                    onTap: () => _selectOffer(offer),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEditor() {
    if (_selectedOffer == null) return const Center(child: Text('Select or Create a Deal'));
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Core Configuration', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Internal Title')),
        const SizedBox(height: 8),
        TextField(controller: _rcIdController, decoration: const InputDecoration(labelText: 'RevenueCat Offering ID')),
        
        const Divider(height: 32),
        Text('Entitlements (The "Deal")', style: Theme.of(context).textTheme.titleLarge),
        Row(
          children: [
            Expanded(child: TextField(controller: _sendsController, decoration: const InputDecoration(labelText: 'Max Sends'))),
            const SizedBox(width: 16),
            Expanded(child: TextField(controller: _forumsController, decoration: const InputDecoration(labelText: 'Max Forums'))),
          ],
        ),
        TextField(controller: _storageController, decoration: const InputDecoration(labelText: 'Storage (MB)')),

        const Divider(height: 32),
        Text('Presentaton Overrides', style: Theme.of(context).textTheme.titleLarge),
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

  Widget _buildPreviewPane() {
    // This constructs a Fake User App View based on the data
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: SingleChildScrollView( 
          padding: const EdgeInsets.all(24),
          child: PhonePreviewWrapper(
            child: _buildMockPaywall(),
          ),
        ),
      ),
    );
  }

  Widget _buildMockPaywall() {
    // This represents what the user would see.
    return Stack(
      children: [
        // Background
        Container(
          color: Colors.white,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
             // Header / Image Placeholder
             Container(
               height: 200,
               color: Colors.grey.shade300,
               child: const Center(child: Icon(Icons.image, size: 50, color: Colors.grey)),
             ),
             
             Padding(
               padding: const EdgeInsets.all(24.0),
               child: Column(
                 children: [
                   Text(
                     _headlineController.text.isEmpty ? 'Unlock Premium' : _headlineController.text,
                     style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
                     textAlign: TextAlign.center,
                   ),
                   const SizedBox(height: 16),
                   Text(
                     _subheadController.text.isEmpty ? 'Get access to more features.' : _subheadController.text,
                     style: const TextStyle(fontSize: 16, color: Colors.black54),
                     textAlign: TextAlign.center,
                   ),
                   const SizedBox(height: 32),
                   
                   // The "Deal" Visualizer
                   Container(
                     padding: const EdgeInsets.all(16),
                     decoration: BoxDecoration(
                       color: Colors.blue.shade50,
                       borderRadius: BorderRadius.circular(12),
                       border: Border.all(color: Colors.blue.shade100),
                     ),
                     child: Column(
                       children: [
                         _buildFeatureRow(Icons.send, '${_sendsController.text} Monthly Sends'),
                         const SizedBox(height: 8),
                         _buildFeatureRow(Icons.forum, '${_forumsController.text} Active Forums'),
                         const SizedBox(height: 8),
                         _buildFeatureRow(Icons.cloud_upload, '${_storageController.text}MB Storage'),
                       ],
                     ),
                   ),
                   
                   const SizedBox(height: 48),
                   ElevatedButton(
                     onPressed: () {},
                     style: ElevatedButton.styleFrom(
                       backgroundColor: _primaryColor,
                       foregroundColor: Colors.white,
                       minimumSize: const Size.fromHeight(50),
                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                     ),
                     child: Text(
                        _ctaController.text.isEmpty ? 'Upgrade Now' : _ctaController.text,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                     ),
                   ),
                   const SizedBox(height: 16),
                   const Text('Restore Purchases', style: TextStyle(color: Colors.grey)),
                 ],
               ),
             ),
          ],
        ),
      ],
    );
  }

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
