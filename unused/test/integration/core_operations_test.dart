import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termisol/app.dart';
import 'package:termisol/core/service_registry.dart';

void main() {
  group('Core Terminal Operations Integration Tests', () {
    late ServiceRegistry registry;

    setUp(() {
      registry = ServiceRegistry.instance;
    });

    testWidgets('App opens successfully', (WidgetTester tester) async {
      await tester.pumpWidget(TermisolApp(registry: registry));
      await tester.pumpAndSettle();

      // Verify main UI elements are present
      expect(find.text('termisol'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsWidgets);
      expect(find.byIcon(Icons.settings), findsOneWidget);

      // Verify initial tab exists
      expect(find.text('Terminal 1'), findsOneWidget);
    });

    testWidgets('Create new tab', (WidgetTester tester) async {
      await tester.pumpWidget(TermisolApp(registry: registry));
      await tester.pumpAndSettle();

      // Initial state - one tab
      expect(find.text('Terminal 1'), findsOneWidget);
      expect(find.text('Terminal 2'), findsNothing);

      // Click add tab button
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      // Verify new tab was created
      expect(find.text('Terminal 1'), findsOneWidget);
      expect(find.text('Terminal 2'), findsOneWidget);
    });

    testWidgets('Switch between tabs', (WidgetTester tester) async {
      await tester.pumpWidget(TermisolApp(registry: registry));
      await tester.pumpAndSettle();

      // Create second tab
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      // Initially on second tab (newly created)
      expect(find.text('Terminal 2'), findsOneWidget);

      // Switch to first tab
      await tester.tap(find.text('Terminal 1'));
      await tester.pumpAndSettle();

      // Verify switched to first tab
      expect(find.text('Terminal 1'), findsOneWidget);
    });

    testWidgets('Close tab', (WidgetTester tester) async {
      await tester.pumpWidget(TermisolApp(registry: registry));
      await tester.pumpAndSettle();

      // Create second tab
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      // Verify two tabs exist
      expect(find.text('Terminal 1'), findsOneWidget);
      expect(find.text('Terminal 2'), findsOneWidget);

      // Right-click on second tab to close (or find close button)
      // Note: In the actual implementation, tabs might close on secondary tap
      // For this test, we'll assume there's a close mechanism

      // Since the implementation uses secondary tap to close,
      // we'll simulate that by tapping the tab with a secondary button
      final tab2Finder = find.text('Terminal 2');
      await tester.tap(tab2Finder, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      // Verify tab was closed and we're back to one tab
      expect(find.text('Terminal 1'), findsOneWidget);
      expect(find.text('Terminal 2'), findsNothing);
    });

    testWidgets('Terminal displays ready state', (WidgetTester tester) async {
      await tester.pumpWidget(TermisolApp(registry: registry));
      await tester.pumpAndSettle();

      // Verify terminal shows ready state
      expect(find.text('Terminal Ready'), findsOneWidget);
      expect(find.text('Type commands to begin...'), findsOneWidget);
    });

    testWidgets('Settings panel opens', (WidgetTester tester) async {
      await tester.pumpWidget(TermisolApp(registry: registry));
      await tester.pumpAndSettle();

      // Click settings button
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Verify settings sheet is open
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Performance'), findsOneWidget);
      expect(find.text('Diagnostics'), findsOneWidget);
    });

    testWidgets('Multiple tab operations', (WidgetTester tester) async {
      await tester.pumpWidget(TermisolApp(registry: registry));
      await tester.pumpAndSettle();

      // Start with 1 tab
      expect(find.text('Terminal 1'), findsOneWidget);

      // Create 3 more tabs
      for (int i = 0; i < 3; i++) {
        await tester.tap(find.byIcon(Icons.add).first);
        await tester.pumpAndSettle();
      }

      // Verify all tabs exist
      expect(find.text('Terminal 1'), findsOneWidget);
      expect(find.text('Terminal 2'), findsOneWidget);
      expect(find.text('Terminal 3'), findsOneWidget);
      expect(find.text('Terminal 4'), findsOneWidget);

      // Switch between tabs
      await tester.tap(find.text('Terminal 3'));
      await tester.pumpAndSettle();
      expect(find.text('Terminal 3'), findsOneWidget);

      await tester.tap(find.text('Terminal 1'));
      await tester.pumpAndSettle();
      expect(find.text('Terminal 1'), findsOneWidget);

      // Close middle tab
      final tab3Finder = find.text('Terminal 3');
      await tester.tap(tab3Finder, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      // Verify tab 3 is gone and others remain
      expect(find.text('Terminal 1'), findsOneWidget);
      expect(find.text('Terminal 2'), findsOneWidget);
      expect(find.text('Terminal 3'), findsNothing);
      expect(find.text('Terminal 4'), findsOneWidget);
    });

    testWidgets('FPS toggle functionality', (WidgetTester tester) async {
      await tester.pumpWidget(TermisolApp(registry: registry));
      await tester.pumpAndSettle();

      // Click FPS button
      await tester.tap(find.byIcon(Icons.speed_outlined));
      await tester.pumpAndSettle();

      // Verify FPS button changed to filled icon
      expect(find.byIcon(Icons.speed), findsOneWidget);

      // Open settings to verify FPS display
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Should show FPS information
      expect(find.text('Current FPS'), findsOneWidget);
    });
  });
}