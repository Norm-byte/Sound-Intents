import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmony_admin/ui/tabs/event_creator_tab.dart';
import 'package:harmony_admin/models/event.dart';

void main() {
  group('EventCreatorTab', () {
    testWidgets('renders core fields and upload button', (tester) async {
      // Arrange: build widget
      // Minimal binding without real Firebase init: rely on lazy getter that won't be used.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: EventCreatorTab(
            onSave: _noopSave,
            events: <Event>[],
          ),
        ),
      ));

      // Assert
  expect(find.textContaining('Event Creator'), findsOneWidget);
  expect(find.text('Upload Blog / Asset'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Event Title *'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Sound URL'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Visual/Image URL'), findsOneWidget);
    });
  });
}

void _noopSave(Event e, {bool publish = false}) {}
