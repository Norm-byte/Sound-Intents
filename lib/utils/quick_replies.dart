// Standard Canned Responses for Admin Support
class QuickReply {
  final String category;
  final String text;

  const QuickReply(this.category, this.text);
}

const List<QuickReply> kQuickReplies = [
  // Greetings
  QuickReply('Greeting', 'Hello, how can I help you today?'),
  QuickReply('Greeting', 'Thank you for contacting Harmony support.'),
  QuickReply('Greeting', 'Hi there! I am looking into your request now.'),

  // Status Updates
  QuickReply('Status', 'I have checked your account details.'),
  QuickReply('Status', 'We are currently investigating the issue you reported.'),
  QuickReply('Status', 'The changes have been applied to your account.'),
  QuickReply('Status', 'We have resolved the issue. Please try again.'),

  // Actions Required
  QuickReply('Action', 'Could you please provide more details?'),
  QuickReply('Action', 'Please try restarting the app to see the changes.'),
  QuickReply('Action', 'Please update to the latest version of the app.'),
  
  // Moderation / Policy
  QuickReply('Policy', 'Please review our community guidelines.'),
  QuickReply('Policy', 'Your content was removed due to a violation of our terms.'),
  QuickReply('Policy', 'Please refrain from using inappropriate language.'),

  // Closing
  QuickReply('Closing', 'Is there anything else I can help you with?'),
  QuickReply('Closing', 'Thank you for being part of our community.'),
  QuickReply('Closing', 'This ticket is now closed. Have a wonderful day!'),
];
