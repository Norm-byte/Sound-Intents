import 'package:flutter/material.dart';

class DocumentationTab extends StatelessWidget {
  const DocumentationTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 32),
          _buildPreface(),
          const SizedBox(height: 32),
          _buildOperationsManual(),
          const SizedBox(height: 32),
          _buildFirebaseExpectations(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.library_books, size: 40, color: Colors.indigo),
            SizedBox(width: 16),
            Text(
              'Operating Manual',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.indigo),
            ),
          ],
        ),
        SizedBox(height: 8),
        Text(
          'Harmony by Intent Admin Dashboard Guide',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildPreface() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About Harmony Admin',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo),
          ),
          SizedBox(height: 16),
          Text(
            'The Harmony by Intent Admin App is a comprehensive management suite designed to oversee the entire Harmony ecosystem. '
            'It serves as the central control room for User Management, Event Scheduling, Content Moderation, and Community Engagement. '
            'Built on Google Firebase, it provides real-time data synchronization across all user devices, ensuring that updates to events, '
            'chat rooms, and media content are reflected instantly in the User App.',
            style: TextStyle(fontSize: 16, height: 1.5),
          ),
          SizedBox(height: 12),
          Text(
            'This application empowers administrators to maintain a safe, engaging, and well-organized environment for all Harmony members. '
            'Through rigorous access controls, verified operator permissions, and intuitive content tools, the Admin App streamlines the '
            'complex task of managing a global digital community.',
            style: TextStyle(fontSize: 16, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationsManual() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How to Operate',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        const SizedBox(height: 16),
        _buildSection(
          'Dashboard',
          'The central hub showing real-time metrics. Use this for a quick health check of the platform (active users, recent joins). Navigate to specific weeks using the week cards.',
        ),
        _buildSection(
          'Event Management',
          'Use the "Event Creator" to draft new sessions. Use "Event Scheduler" to place them on the calendar. \n'
          '• Events map to Firestore documents automatically.\n'
          '• Ensuring correct time zones is handled by the system, but always verify UTC offsets if unsure.',
        ),
        _buildSection(
          'User Management',
          '• **Guest Users**: Every installation of the User App automatically generates a "Guest" profile. This allows users to explore the app immediately. These users appear in your list to give you an accurate count of total installs/reach.\n'
          '• **Subscriptions**: Handled automatically via revenue partners. If a user cancels or fails payment, they are downgraded to "Free" status but **NOT** deleted. This allows them to easily resubscribe later without losing their settings.\n'
          '• **Data Retention**: We currently retain inactive accounts indefinitely to facilitate easy return. Use the "Delete User" action in the User Detail panel only for spam removal or GDPR requests.',
        ),
        _buildSection(
          'User Management',
          'View, edit, and moderate user accounts. \n'
          '• Search users by email or name.\n'
          '• Use the "Ban/Suspend" functions responsibly.\n'
          '• "Notes" on user profiles are private to admins.',
        ),
        _buildSection(
          'Chat Rooms',
          'Create and manage community chat spaces.\n'
          '• Toggle "Maintenance Mode" to lock rooms during updates or issues.\n'
          '• Pin crucial messages to the top of rooms.',
        ),
        _buildSection(
          'Translation Toggle (User App)',
          'Harmony now includes a per-device Translation Toggle in Community Room, published Chat Rooms, and Support Chat.\n'
          '• Toggle ON: The app translates incoming message text for the reader based on their phone language.\n'
          '• Toggle OFF: Users see original message text as posted.\n'
          '• Sender behavior: Users can write in their own language; readers choose whether to view translated text.\n'
          '• Current language targets: English, French, German, Dutch, Spanish, Romanian, Swedish, and Hindi.\n'
          '• Fallback behavior: Unsupported locales currently fall back to English output.\n'
          '• Operational note: Translation is intended for engagement and accessibility, but moderators should still review original context when handling sensitive reports.',
        ),
        _buildSection(
          'Admin Translation Status',
          'The Translation Toggle is currently implemented in the User App message surfaces.\n'
          '• Included now: Community Room, Chat Rooms, and Support Chat for end users.\n'
          '• Next phase (admin-side): add the same translate control in Admin moderation/reply views so operators can read and respond faster across languages.',
        ),
        _buildSection(
          'Media Library',
          'Upload and manage assets (videos, images). \n'
          '• Linking YouTube videos here makes them available for "Cinema Mode" events.',
        ),
        _buildSection(
          'Admin Management',
          'Create new operators and assign permissions.\n'
          '• Use checkboxes to grant tab-specific access.\n'
          '• VIP Codes are generated automatically for new admins.',
        ),
        _buildSection(
          'Legal & Compliance',
          'Manage Terms of Service and Privacy Policy PDF documents.\n'
          '• Secured area requiring VIP password to edit.',
        ),
        _buildSection(
          'Monetization & Paywalls',
          'Harmony uses RevenueCat for In-App Purchases. This allows for flexible management of subscriptions without constant app updates.\n\n'
          '**Adding New Paywalls:**\n'
          '1. Log in to the [RevenueCat Dashboard](https://app.revenuecat.com).\n'
          '2. Go to **Products** and define your new store products (e.g., Apple App Store / Google Play Console IDs).\n'
          '3. Go to **Entitlements**. The app currently checks for the ID: `Harmony by Intent Pro`. \n'
          '   - To change pricing or trial duration: Update the "Offering" in RevenueCat. No app update needed.\n'
          '   - To add a NEW tier (e.g., "Platinum"): Create a new Entitlement in RevenueCat. **IMPORTANT:** You must also contact the developer to update the app code (`subscription_service.dart`) to recognize this new tier.\n'
          '4. **Paywall UI:** We use the native Paywall UI. You can customize the look (colors, images) directly in RevenueCat\'s "Paywalls" section. These changes reflect instantly in the app.\n\n'
          '### Membership & Upgrade Triggers\n'
          'The app operates on a "Freemium" model designed to encourage deep engagement before asking for payment.\n\n'
          '**The "51 Words" Trigger:**\n'
          'Free users have a daily limit of 50 interactions (words/messages/inputs). Upon hitting the 51st interaction, the app will:\n'
          '- Pause their action.\n'
          '- Display a prompt explaining they have reached the daily limit for free members.\n'
          '- Offer a button to "Upgrade to Pro" which launches the Paywall.\n\n'
          '**Expansion & Free Trials:**\n'
          '- **Free Trial:** The standard "Pro" offering (configured in RevenueCat) usually includes a Free Trial period (e.g., 3 or 7 days). This allows users to experience the "Unlimited" features without immediate billing. Apple/Google handles the transition from Trial to Paid automatically.\n'
          '- **Expansion Scheme:** This refers to the content scaling. As users upgrade, they unlock not just "more words" but access to specialized events, deeper archive access, and potentially (in future updates) higher-tier "Platinum" content. The system recognizes the upgrade instantly via RevenueCat and lifts the 50-word cap immediately.',
        ),
        _buildSection(
          'User Privacy & Data Handling',
          'A key principle of Harmony by Intent is data minimization and security.\n\n'
          '**Subscriptions & Financial Data:**\n'
          'All financial transactions (credit card numbers, bank details) are handled **exclusively** by the Apple App Store or Google Play Store. \n'
          '- The Harmony app **NEVER** sees, stores, or touches user banking info.\n'
          '- We receive only a "Receipt" from the store confirming the user has paid.\n'
          '- Cancellations and refunds are managed by the user via their Phone Settings, not the app.\n\n'
          '**Personal Profile Information:**\n'
          'User profiles (Name, Email, Photo) are stored securely in Google Firebase Auth & Firestore.\n'
          '- Passwords are encrypted by Google; admins cannot see them.\n'
          '- Users have full control to edit their profile or "Delete Account" anytime within the app settings.\n\n'
          '**Simplifying the Process:**\n'
          'The "Auto-Subscribe" feature is native to the Mobile Stores. When a user initially signs up for the Trial or Subscription, they authorize Apple/Google to bill them monthly. This ensures the "Plan" updates automatically without manual admin intervention. If payment fails, RevenueCat tells the app to lock "Pro" features automatically.'
        ),
      ],
    );
  }

  Widget _buildFirebaseExpectations() {
    return const Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Text(
              'Firebase & Technical Considerations',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text('• Real-time Sync: Changes made here appear instantly on user phones. Double-check edits before saving.', style: TextStyle(height: 1.5)),
            Text('• Offline Mode: The Admin app works best with a stable internet connection. Data changes made offline will sync when connectivity is restored.', style: TextStyle(height: 1.5)),
            Text('• Storage Rules: Large media uploads go to Firebase Storage. Ensure files are optimized for web/mobile viewing.', style: TextStyle(height: 1.5)),
            Text('• Security: Do not share your Admin Password or VIP Code. Access is logged.', style: TextStyle(height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, color: Colors.green.shade600, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(content, style: TextStyle(color: Colors.grey.shade800, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
